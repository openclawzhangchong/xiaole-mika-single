"""网关的任务层：把 Mika 的一次性目标变成可查询、可取消、可订阅的网关任务。"""

from __future__ import annotations

import threading
import time
import uuid
from collections import OrderedDict
from concurrent.futures import ThreadPoolExecutor

from .phone import PhoneError, TERMINAL

GATEWAY_TERMINAL = TERMINAL | {"timeout"}
VALID_STATUS = {"starting", "queued", "running", "paused", "waiting_for_answer",
                "waiting_on_phone", "done", "failed", "cancelled", "timeout", "unknown"}
MAX_GOAL = 4000          # Mika 的 RemoteTaskService.MAX_GOAL
MAX_TASKS_KEPT = 200


def now_ms() -> int:
    return int(time.time() * 1000)


class TaskRecord:
    def __init__(self, goal: str, session_id: str | None, conversation: str | None,
                 timeout_s: int, request_id: str, log):
        self.id = request_id
        self.goal = goal
        self.session_id = session_id
        self.conversation = conversation
        self.timeout_s = timeout_s
        self.created_at_ms = now_ms()
        self.submitted_at_ms: int | None = None
        self.finished_at_ms: int | None = None
        self.deadline_at_ms = self.created_at_ms + timeout_s * 1000
        self.status = "queued"
        self.mika_status: str | None = None
        self.progress: str | None = None
        self.step: str | None = None
        self.question: str | None = None
        self.waiting_for: str | None = None
        self.note: str | None = None
        self.answer: str | None = None
        self.error: dict | None = None
        self.attempts = 0
        self.cancel_requested = False
        self.cancel_sent = False
        self.recoverable = False
        self.events: list[dict] = []
        self._seq = 0
        self._cond = threading.Condition()
        self._lock = threading.Lock()
        self._log = log

    # ---- 状态迁移（都在锁内，并广播事件）----

    def _event(self, kind: str, data: dict) -> None:
        with self._cond:
            self._seq += 1
            event = {"seq": self._seq, "ts_ms": now_ms(), "event": kind, "data": data}
            self.events.append(event)
            self._cond.notify_all()

    @property
    def finished(self) -> bool:
        return self.status in GATEWAY_TERMINAL

    def _set_status(self, status: str, **fields) -> bool:
        with self._lock:
            if self.status == status and not fields:
                return False
            changed = self.status != status
            self.status = status
            for key, value in fields.items():
                setattr(self, key, value)
            if status in GATEWAY_TERMINAL and self.finished_at_ms is None:
                self.finished_at_ms = now_ms()
        if changed or fields:
            self._event("status", {"status": status, **fields})
        return changed

    def apply_snapshot(self, snap: dict) -> None:
        """把 Mika 的任务快照映射成网关状态。"""
        mika = snap.get("status")
        if mika not in VALID_STATUS - {"timeout", "unknown"}:
            raise PhoneError("upstream_protocol", f"手机返回了未知任务状态：{mika!r}", 502)
        self.mika_status = mika
        self.conversation = snap.get("conversation") or self.conversation
        updates: dict = {}
        for field, key in (("progress", "progress"), ("step", "step"), ("question", "question"),
                           ("waiting_for", "waiting_for"), ("note", "note")):
            value = snap.get(key)
            if value != getattr(self, field):
                setattr(self, field, value)
                updates[field] = value
        changed_progress = bool(updates)
        if mika == "done":
            self.answer = snap.get("answer")
            self._set_status("done", answer=self.answer)
            self._event("result", {"task_id": self.id, "status": "done", "answer": self.answer,
                                   "verified": snap.get("verified")})
            return
        if mika == "failed":
            self.error = {"code": str(snap.get("failure_kind") or "failed"),
                          "message": str(snap.get("reason") or "手机执行失败")}
            self._set_status("failed", error=self.error)
            self._event("result", {"task_id": self.id, "status": "failed", **self.error})
            return
        if mika == "cancelled":
            self._set_status("cancelled")
            self._event("result", {"task_id": self.id, "status": "cancelled"})
            return
        self._set_status(mika)
        if changed_progress:
            self._event("progress", {k: v for k, v in updates.items()})

    def fail(self, code: str, message: str, *, may_still_run: bool = False) -> None:
        self.error = {"code": code, "message": message}
        self.recoverable = may_still_run
        self._set_status("failed", error=self.error, recoverable=may_still_run)
        self._event("error", {"task_id": self.id, "code": code, "message": message,
                              "may_still_run_on_phone": may_still_run})

    def mark_timeout(self, message: str) -> None:
        self.error = {"code": "task_timeout", "message": message}
        self._set_status("timeout", error=self.error)
        self._event("result", {"task_id": self.id, "status": "timeout", **self.error})

    def mark_unknown(self, message: str) -> None:
        self.error = {"code": "device_offline", "message": message, "may_still_run_on_phone": True}
        self.recoverable = True
        self._set_status("unknown", error=self.error, recoverable=True)
        self._event("error", {"task_id": self.id, "code": "device_offline", "message": message,
                              "may_still_run_on_phone": True})

    def snapshot(self) -> dict:
        with self._lock:
            return {
                "task_id": self.id,
                "session_id": self.session_id,
                "goal": self.goal,
                "conversation": self.conversation,
                "status": self.status,
                "mika_status": self.mika_status,
                "created_at_ms": self.created_at_ms,
                "updated_at_ms": now_ms(),
                "deadline_at_ms": self.deadline_at_ms,
                "progress": self.progress,
                "step": self.step,
                "question": self.question,
                "waiting_for": self.waiting_for,
                "note": self.note,
                "answer": self.answer,
                "error": self.error,
                "cancel_requested": self.cancel_requested,
                "attempts": self.attempts,
                "finished": self.finished,
                "duration_ms": (self.finished_at_ms or now_ms()) - self.created_at_ms,
            }


class TaskManager:
    def __init__(self, phone, *, timeout_default: int = 300, max_concurrent: int = 4,
                 wait_window: int = 20, max_pending: int = 32, log=None):
        self.phone = phone
        self.timeout_default = timeout_default
        self.wait_window = wait_window
        self.max_pending = max_pending
        self.log = log or (lambda level, msg: None)
        self._tasks: "OrderedDict[str, TaskRecord]" = OrderedDict()
        self._lock = threading.Lock()
        self._pool = ThreadPoolExecutor(max_workers=max_concurrent, thread_name_prefix="task")

    # ---- 提交与查询 ----

    @staticmethod
    def _clean_goal(goal) -> str:
        if not isinstance(goal, str) or not goal.strip():
            raise PhoneError("invalid_request", "goal 必填，且不能是空白字符串。", 400)
        clean = goal.strip()
        if len(clean) > MAX_GOAL:
            raise PhoneError("invalid_request", f"goal 太长（上限 {MAX_GOAL} 字符）。", 400)
        return clean

    def submit(self, goal, session_id=None, conversation=None, timeout_s=None, request_id=None) -> tuple[dict, bool]:
        clean = self._clean_goal(goal)
        if session_id is not None and (not isinstance(session_id, str) or len(session_id) > 200):
            raise PhoneError("invalid_request", "session_id 必须是不超过 200 字符的字符串。", 400)
        if conversation is not None:
            if not isinstance(conversation, str) or not conversation.startswith("mcp-"):
                raise PhoneError("invalid_request", "conversation 必须是之前任务返回的 mcp-<uuid>。", 400)
        if timeout_s is None:
            timeout_s = self.timeout_default
        if not isinstance(timeout_s, int) or not 30 <= timeout_s <= 1800:
            raise PhoneError("invalid_request", "timeout_s 必须是 30..1800 的整数。", 400)
        if request_id is None:
            request_id = str(uuid.uuid4())
        else:
            try:
                if str(uuid.UUID(request_id)) != request_id:
                    raise ValueError
            except (ValueError, AttributeError, TypeError):
                raise PhoneError("invalid_request", "request_id 必须是小写 canonical UUID。", 400) from None

        # 提交前先探活：手机不可达就立刻返回明确错误，不建"假任务"。
        self.phone.probe_fast()

        with self._lock:
            existing = self._tasks.get(request_id)
            if existing is not None:
                return existing.snapshot(), False
            if sum(1 for t in self._tasks.values() if not t.finished) >= self.max_pending:
                raise PhoneError("too_many_tasks", "网关里未完成的任务太多，稍后再提交。", 429)
            record = TaskRecord(clean, session_id, conversation, timeout_s, request_id, self.log)
            self._tasks[request_id] = record
            self._trim()
        record._event("accepted", {"task_id": record.id, "status": record.status})
        self._pool.submit(self._run, record, True)
        return record.snapshot(), True

    def get(self, task_id: str) -> TaskRecord:
        with self._lock:
            record = self._tasks.get(task_id)
        if record is None:
            raise PhoneError("task_not_found", f"网关没有任务 {task_id}。", 404)
        if record.status == "unknown" and record.recoverable:
            # 之前因断连没能确认，现在直连手机核对一次；还在跑就把轮询接回去。
            try:
                snap = self.phone.get_task(task_id)
                record.apply_snapshot(snap)
                record.recoverable = False
                if not record.finished:
                    self._pool.submit(self._run, record, False)
            except PhoneError as exc:
                self.log("warn", f"任务 {task_id} 复核失败：{exc.code}")
        return record

    def list(self, limit: int = 20) -> list[dict]:
        with self._lock:
            items = list(self._tasks.values())[-limit:]
        return [t.snapshot() for t in reversed(items)]

    def cancel(self, task_id: str) -> dict:
        record = self.get(task_id)
        if record.finished:
            return {"task_id": record.id, "accepted": False, "status": record.status}
        record.cancel_requested = True
        record._event("cancel_requested", {"task_id": record.id})
        return {"task_id": record.id, "accepted": True, "status": record.status}

    def answer(self, task_id: str, text) -> dict:
        record = self.get(task_id)
        if not isinstance(text, str) or not text.strip():
            raise PhoneError("invalid_request", "text 必填。", 400)
        if record.finished:
            raise PhoneError("task_finished", "任务已结束，不能再回答。", 409)
        self.phone.answer_task(task_id, text.strip())
        record._event("answered", {"task_id": record.id, "text": text.strip()})
        return record.snapshot()

    def events_since(self, task_id: str, since: int) -> list[dict]:
        record = self.get(task_id)
        with record._cond:
            return [e for e in record.events if e["seq"] > since]

    def wait_event(self, task_id: str, since: int, timeout: float = 15.0) -> list[dict]:
        record = self.get(task_id)
        with record._cond:
            if not any(e["seq"] > since for e in record.events):
                record._cond.wait(timeout)
            return [e for e in record.events if e["seq"] > since]

    # ---- 后台执行 ----

    def _run(self, record: TaskRecord, need_submit: bool) -> None:
        try:
            if need_submit:
                self._submit_to_phone(record)
            if record.finished or record.mika_status is None:
                return
            self._poll(record)
        except PhoneError as exc:
            self.log("error", f"任务 {record.id} 结束于 {exc.code}：{exc.message}")
            if record.status == "unknown":
                return
            if exc.code in {"device_offline", "device_unauthorized", "port_forward_broken", "adb_error",
                            "adb_unavailable", "adb_timeout"}:
                record.mark_unknown(exc.message)
            elif exc.ambiguous:
                record.fail("outcome_unknown", exc.message, may_still_run=True)
            else:
                record.fail(exc.code, exc.message)
        except Exception as exc:  # 兜底：不让一个任务把线程池搞哑
            self.log("error", f"任务 {record.id} 内部异常：{exc!r}")
            record.fail("internal_error", f"网关内部错误：{exc!r}")

    def _submit_to_phone(self, record: TaskRecord) -> None:
        self.log("info", f"提交任务 {record.id} 到手机：{record.goal[:60]}")
        snap = self.phone.start_task(record.goal, record.id, record.conversation)
        record.attempts += 1
        record.submitted_at_ms = now_ms()
        record.apply_snapshot(snap)

    def _poll(self, record: TaskRecord) -> None:
        while not record.finished:
            if record.cancel_requested and not record.cancel_sent:
                record.cancel_sent = True
                try:
                    receipt = self.phone.cancel_task(record.id)
                    self.log("info", f"取消任务 {record.id}：accepted={receipt.get('accepted')}")
                except PhoneError as exc:
                    record.note = f"取消失败：{exc.message}"
                    record._event("progress", {"note": record.note})
            remaining_ms = record.deadline_at_ms - now_ms()
            if remaining_ms <= 0:
                record.mark_timeout(f"超过网关时限 {record.timeout_s}s，已向手机发出取消。")
                try:
                    self.phone.cancel_task(record.id)
                except PhoneError as exc:
                    self.log("warn", f"超时后取消失败：{exc.code} {exc.message}")
                return
            # 单次等待不超过剩余时间，超时判定误差控制在一秒内。
            window = max(1, min(self.wait_window, int(remaining_ms / 1000)))
            snap = self.phone.wait_task(record.id, window)
            record.apply_snapshot(snap)

    def _trim(self) -> None:
        if len(self._tasks) <= MAX_TASKS_KEPT:
            return
        for key in list(self._tasks.keys()):
            if len(self._tasks) <= MAX_TASKS_KEPT:
                break
            if self._tasks[key].finished:
                del self._tasks[key]
