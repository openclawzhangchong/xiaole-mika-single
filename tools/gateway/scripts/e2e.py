"""端到端验证脚本：并发提交、轮询、对照结果与 id 是否串台。

用法：python scripts/e2e.py --base http://127.0.0.1:8790
"""

from __future__ import annotations

import argparse
import json
import threading
import time
import urllib.error
import urllib.request

TERMINAL = {"done", "failed", "cancelled", "timeout"}


def call(base, path, body=None, timeout=30):
    data = None if body is None else json.dumps(body, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(base + path, data=data, method="POST" if body is not None else "GET",
                                 headers={"Content-Type": "application/json", "Accept": "application/json"})
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(req, timeout=timeout) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read())


def submit(base, goal, session_id, out, index):
    started = time.time()
    status, payload = call(base, "/goal", {"goal": goal, "session_id": session_id, "timeout_s": 600})
    out[index] = {"http_status": status, "submit_ms": round((time.time() - started) * 1000), "payload": payload}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8790")
    ap.add_argument("--poll", type=float, default=3.0)
    ap.add_argument("--max-wait", type=float, default=600)
    args = ap.parse_args()

    goals = {
        0: "只读查询：这台手机的屏幕分辨率（执行 wm size）是多少？只回答分辨率，不要打开任何应用。",
        1: "只读查询：这台手机的 CPU/SoC 型号（读 ro.soc.model 或 ro.hardware）是什么？只回答型号，不要打开任何应用。",
    }
    results: dict[int, dict] = {}
    threads = [threading.Thread(target=submit, args=(args.base, g, f"e2e-concurrent-{i}", results, i))
               for i, g in goals.items()]
    t0 = time.time()
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    ids = {}
    for i in sorted(results):
        r = results[i]
        print(f"[submit {i}] HTTP {r['http_status']} {r['submit_ms']}ms -> "
              f"{r['payload'].get('task_id') or r['payload'].get('error')}")
        if "task_id" in r["payload"]:
            ids[i] = r["payload"]["task_id"]
    if len(ids) != 2:
        print("提交失败，无法继续并发验证")
        return 1

    order = [0, 1]
    last = {i: None for i in ids}
    final: dict[int, dict] = {}
    while time.time() - t0 < args.max_wait:
        done = 0
        for i in order:
            _, snap = call(args.base, f"/task/{ids[i]}")
            if snap.get("status") != last[i]:
                elapsed = time.time() - t0
                print(f"[{elapsed:6.1f}s] {ids[i][:8]} status={snap.get('status'):<18} "
                      f"progress={(snap.get('progress') or '')[:60]}")
                last[i] = snap.get("status")
            if snap.get("finished"):
                done += 1
                final[i] = snap
        if done == len(ids):
            break
        time.sleep(args.poll)

    print("\n=== 结果对照 ===")
    ok = True
    elapsed_total = round(time.time() - t0, 2)
    for i in order:
        snap = final.get(i) or call(args.base, f"/task/{ids[i]}")[1]
        print(f"task[{i}] id={snap['task_id']} status={snap['status']} duration={snap.get('duration_ms')}ms")
        print(f"  goal   : {goals[i]}")
        print(f"  answer : {(snap.get('answer') or snap.get('error') or '')}")
        if snap["task_id"] != ids[i] or snap.get("status") != "done":
            ok = False
    print(f"\n总耗时 {elapsed_total}s")
    print("并发隔离：" + ("通过（两个任务的 id 与结果一一对应）" if ok else "未通过"))

    evidence = {"goals": {str(k): v for k, v in goals.items()},
                "submit": {str(k): v for k, v in results.items()},
                "final": {str(k): v for k, v in final.items()},
                "total_seconds": elapsed_total}
    with open("evidence/concurrent.json", "w", encoding="utf-8") as fh:
        json.dump(evidence, fh, ensure_ascii=False, indent=2)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
