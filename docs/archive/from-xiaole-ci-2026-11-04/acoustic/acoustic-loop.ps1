# 声学回环验证 · 播放与采集（v2）
# 用法（69 装机并恢复配置后）：
#   powershell -File acoustic-loop.ps1 -Wav speech-zh-g70.wav -Runs 5 -IntervalSec 7 -Tag g70
#   powershell -File acoustic-loop.ps1 -Wav speech-zh-g70.wav -Runs 5 -Tag g70 -GrantMic   # 首次授权麦克风
#
# 判定：5 次里至少 4 次出现「App 开始录音 + App 发声」才算过（-MinPass 4）。
# 证据：每次播放后的 dumpsys audio 差分 + 截图 + summary.csv + logcat 原始日志。
#
# 为什么用 dumpsys audio：实测 6.11.12-mika1（versionCode 67）的 release 包
# 在 logcat 里**没有任何 Dart 日志**（`logcat -s flutter` 为空），
# 所以不能把判定绑在 `[KEEPALIVE]/[TEXTSPLIT]` 这类日志上；音频通路与 UI 才是硬证据。

param(
    [string]$Serial   = '36c77fb6',
    [string]$Wav      = 'speech-zh.wav',
    [int]$Runs        = 5,
    [int]$IntervalSec = 7,
    [string]$Tag      = 'default',
    [int]$MinPass     = 4,
    [string]$OutDir   = (Join-Path $PSScriptRoot 'runs'),
    [switch]$GrantMic,
    [switch]$Discover
)

$ErrorActionPreference = 'Stop'
$WavPath = if (Test-Path $Wav) { (Resolve-Path $Wav).Path } else { Join-Path $PSScriptRoot $Wav }
if (-not (Test-Path $WavPath)) { throw "音源不存在: $WavPath" }

$RunDir = Join-Path $OutDir ("{0}-{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $Tag)
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
$LogFile   = Join-Path $RunDir 'logcat.txt'
$CsvFile   = Join-Path $RunDir 'summary.csv'
$Pkg       = 'com.zcstudy.xiaole'

function A { adb -s $Serial @args }
function Mark([string]$m) { adb -s $Serial shell log -t ACOUSTIC_MARK $m | Out-Null }
function AudioDump([string]$path) { adb -s $Serial shell dumpsys audio > $path }

# ---------- 0. 前置检查 ----------
$devs = (adb devices | Select-String '\sdevice$').Count
if ($devs -gt 1) { "检测到 $devs 台设备，已锁定 -s $Serial（其它设备不碰）" }

$pkgLine = (adb -s $Serial shell dumpsys package $Pkg | Select-String 'versionCode=' | Select-Object -First 1).Line.Trim()
$fg      = (adb -s $Serial shell dumpsys activity activities | Select-String 'mResumedActivity' | Select-Object -First 1).Line.Trim()
$zen     = (adb -s $Serial shell settings get global zen_mode).Trim()
$wake    = (adb -s $Serial shell dumpsys power | Select-String 'mWakefulness=' | Select-Object -First 1).Line.Trim()
$mic     = (adb -s $Serial shell appops get $Pkg RECORD_AUDIO).Trim()

Write-Output "设备: $Serial | $pkgLine"
Write-Output "前台: $fg"
Write-Output "zen_mode=$zen | $wake"
Write-Output "麦克风: $mic"

if ($GrantMic) {
    adb -s $Serial shell pm grant $Pkg android.permission.RECORD_AUDIO | Out-Null
    $mic = (adb -s $Serial shell appops get $Pkg RECORD_AUDIO).Trim()
    Write-Output "已执行 pm grant RECORD_AUDIO => $mic"
}
if ($mic -match 'ignore') {
    Write-Output "⚠ RECORD_AUDIO 被拒绝：VAD 不可能触发。69 装机后用 -GrantMic 或首次语音时点「允许」。"
}
if ($fg -notmatch 'com\.zcstudy\.xiaole') {
    Write-Output "App 不在前台，拉起 MainActivity"
    adb -s $Serial shell am start -n $Pkg/.MainActivity | Out-Null
    Start-Sleep -Seconds 4
}
if ($wake -notmatch 'Awake') { adb -s $Serial shell input keyevent KEYCODE_WAKEUP | Out-Null; Start-Sleep -Seconds 2 }

# ---------- 1. 起 logcat + 采集音频基线 ----------
adb -s $Serial logcat -c
$logProc = Start-Process -FilePath 'adb' -ArgumentList @('-s', $Serial, 'logcat', '-v', 'time') `
    -RedirectStandardOutput $LogFile -RedirectStandardError (Join-Path $RunDir 'logcat.err.txt') -NoNewWindow -PassThru
Start-Sleep -Milliseconds 600
Mark "SESSION START tag=$Tag runs=$Runs wav=$(Split-Path $WavPath -Leaf)"
AudioDump (Join-Path $RunDir 'audio-run0.txt')

try { Add-Type -AssemblyName System.Windows.Extensions -ErrorAction Stop } catch {}
$player = New-Object Media.SoundPlayer $WavPath
$rows = @()

# ---------- 2. 逐次播放 ----------
for ($i = 1; $i -le $Runs; $i++) {
    Mark "RUN $i START"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Write-Output ("[{0}] RUN {1} 播放 {2}" -f (Get-Date -Format 'HH:mm:ss'), $i, (Split-Path $WavPath -Leaf))
    $player.PlaySync()
    $sw.Stop()
    Start-Sleep -Seconds $IntervalSec

    Mark "RUN $i END"
    AudioDump (Join-Path $RunDir ("audio-run{0}.txt" -f $i))
    adb -s $Serial shell screencap -p "/sdcard/shot-$i.png" | Out-Null
    adb -s $Serial pull "/sdcard/shot-$i.png" (Join-Path $RunDir "shot-$i.png") | Out-Null
    adb -s $Serial shell rm "/sdcard/shot-$i.png" | Out-Null

    # ---- 本次新增的音频事件 ----
    $prev = Get-Content (Join-Path $RunDir ("audio-run{0}.txt" -f ($i - 1))) -Encoding UTF8 -ErrorAction SilentlyContinue
    $cur  = Get-Content (Join-Path $RunDir ("audio-run{0}.txt" -f $i)) -Encoding UTF8 -ErrorAction SilentlyContinue
    $new  = $cur | Where-Object { $prev -notcontains $_ }
    $rec  = @($new | Where-Object { $_ -match "pack:$Pkg" -and $_ -match 'rec (start|update)|recording|startRecording' }).Count
    $play = @($new | Where-Object { $_ -match "pack:$Pkg|callingPack=$Pkg" -and $_ -match 'requestAudioFocus|player|AudioTrack|start' }).Count

    $rows += [pscustomobject]@{
        Run = $i; PlaySec = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        AppRec = $rec; AppPlay = $play
        Result = if ($rec -gt 0 -and $play -gt 0) { 'PASS' } else { 'FAIL' }
    }
}
Mark "SESSION END"

# ---------- 3. 停 logcat ----------
Start-Sleep -Milliseconds 800
if (-not $logProc.HasExited) { Stop-Process -Id $logProc.Id -Force }
Start-Sleep -Milliseconds 300

# ---------- 4. 汇总 ----------
$appLog = @(Get-Content $LogFile -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -match 'flutter' })
Write-Output ("Dart 日志行数={0}（0 表示该包 release 不输出 Dart 日志，判定只依赖音频通路+截图）" -f $appLog.Count)

$rows | Format-Table -AutoSize
$rows | Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8

$passCount = @($rows | Where-Object Result -eq 'PASS').Count
Write-Output ("PASS {0}/{1}（阈值 {2}/{1}）" -f $passCount, $Runs, $MinPass)
Write-Output ("结论: " + $(if ($passCount -ge $MinPass) { 'PASS' } else { 'FAIL' }) + "  证据目录: $RunDir")

if ($Discover) {
    Write-Output "`n== Discover：本次会话里 App 相关音频事件 =="
    for ($i = 1; $i -le $Runs; $i++) {
        $prev = Get-Content (Join-Path $RunDir ("audio-run{0}.txt" -f ($i - 1))) -Encoding UTF8 -ErrorAction SilentlyContinue
        $cur  = Get-Content (Join-Path $RunDir ("audio-run{0}.txt" -f $i)) -Encoding UTF8 -ErrorAction SilentlyContinue
        ($cur | Where-Object { $prev -notcontains $_ -and $_ -match "$Pkg" }) | Select-Object -First 20 | ForEach-Object { "RUN $i : $($_.Trim())" }
    }
}

if ($passCount -lt $MinPass) { exit 1 }
