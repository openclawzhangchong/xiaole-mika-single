# 声学回环验证 · 播放与采集
# 用法（69 装机并恢复配置后）：
#   powershell -File acoustic-loop.ps1 -Wav speech-zh-g70.wav -Runs 5 -IntervalSec 7 -Tag g70
# 判定：5 次里至少 4 次跑完 VAD → listen start → stt → tts 才算过（-MinPass 4）。
# 证据：logcat 原始日志 + 每次播放后的截图 + summary.csv。
#
# 关键设计：
#   1. 用 `adb shell log -t ACOUSTIC_MARK` 往设备日志里打窗口标记，避免电脑/手机时钟不同步导致切窗口错位。
#   2. 不改电脑系统音量；音量档位用 wav 增益（speech-zh-g50/g70/g90.wav）实现，可复现。
#   3. 多设备必须显式 -Serial（默认 36c77fb6），其它设备一律不碰。

param(
    [string]$Serial      = '36c77fb6',
    [string]$Wav         = 'speech-zh.wav',
    [int]$Runs           = 5,
    [int]$IntervalSec    = 7,
    [string]$Tag         = 'default',
    [int]$MinPass        = 4,
    [string]$OutDir      = (Join-Path $PSScriptRoot 'runs'),
    [switch]$Discover
)

$ErrorActionPreference = 'Stop'
$WavPath = if (Test-Path $Wav) { (Resolve-Path $Wav).Path } else { Join-Path $PSScriptRoot $Wav }
if (-not (Test-Path $WavPath)) { throw "音源不存在: $WavPath" }

$RunDir = Join-Path $OutDir ("{0}-{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $Tag)
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
$LogFile = Join-Path $RunDir 'logcat.txt'
$CsvFile = Join-Path $RunDir 'summary.csv'

function A { adb -s $Serial @args }
function Mark([string]$m) { adb -s $Serial shell log -t ACOUSTIC_MARK $m | Out-Null }

# ---------- 0. 前置检查 ----------
$devs = (adb devices | Select-String '\sdevice$').Count
if ($devs -gt 1) { "检测到 $devs 台设备，已锁定 -s $Serial（其它设备不碰）" }
$pkg = (adb -s $Serial shell dumpsys package com.zcstudy.xiaole | Select-String 'versionCode=' | Select-Object -First 1).Line.Trim()
$fg  = (adb -s $Serial shell dumpsys activity activities | Select-String 'mResumedActivity' | Select-Object -First 1).Line.Trim()
$zen = (adb -s $Serial shell settings get global zen_mode).Trim()
$wake = (adb -s $Serial shell dumpsys power | Select-String 'mWakefulness=' | Select-Object -First 1).Line.Trim()
Write-Output "设备: $Serial | $pkg"
Write-Output "前台: $fg"
Write-Output "zen_mode=$zen | $wake"

if ($fg -notmatch 'com\.zcstudy\.xiaole') {
    Write-Output "App 不在前台，拉起 MainActivity"
    adb -s $Serial shell am start -n com.zcstudy.xiaole/.MainActivity | Out-Null
    Start-Sleep -Seconds 4
}
if ($wake -notmatch 'Awake') { adb -s $Serial shell input keyevent KEYCODE_WAKEUP | Out-Null; Start-Sleep -Seconds 2 }
if ($zen -ne '0') { Write-Output "⚠ 设备处于勿扰/静音(zen_mode=$zen)，可能影响提示音但不影响录音" }

# ---------- 1. 起 logcat ----------
adb -s $Serial logcat -c
$logProc = Start-Process -FilePath 'adb' -ArgumentList @('-s', $Serial, 'logcat', '-v', 'time') `
    -RedirectStandardOutput $LogFile -RedirectStandardError (Join-Path $RunDir 'logcat.err.txt') -NoNewWindow -PassThru
Start-Sleep -Milliseconds 600
Mark "SESSION START tag=$Tag runs=$Runs wav=$(Split-Path $WavPath -Leaf)"

$player = $null
try { Add-Type -AssemblyName System.Windows.Extensions -ErrorAction Stop } catch {}
$player = New-Object Media.SoundPlayer $WavPath
$wavDur = 12.56  # 由 tts-gen.ps1 打印，播放前会按实测覆盖
$rec = @()

# ---------- 2. 逐次播放 ----------
for ($i = 1; $i -le $Runs; $i++) {
    Mark "RUN $i START"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Write-Output ("[{0}] RUN {1} 播放 {2}" -f (Get-Date -Format 'HH:mm:ss'), $i, (Split-Path $WavPath -Leaf))
    $player.PlaySync()
    $sw.Stop()
    Start-Sleep -Seconds $IntervalSec

    Mark "RUN $i END"
    $shot = "shot-$i.png"
    adb -s $Serial shell screencap -p "/sdcard/$shot" | Out-Null
    adb -s $Serial pull "/sdcard/$shot" (Join-Path $RunDir $shot) | Out-Null
    adb -s $Serial shell rm "/sdcard/$shot" | Out-Null

    $rec += [pscustomobject]@{ Run = $i; PlaySec = [math]::Round($sw.Elapsed.TotalSeconds, 2); Shot = $shot }
}
Mark "SESSION END"

# ---------- 3. 停 logcat 并分析 ----------
Start-Sleep -Milliseconds 800
if (-not $logProc.HasExited) { Stop-Process -Id $logProc.Id -Force }
Start-Sleep -Milliseconds 300

$lines = @(Get-Content $LogFile -Encoding UTF8 -ErrorAction SilentlyContinue)
$appLines = @($lines | Where-Object { $_ -match 'flutter|com\.zcstudy\.xiaole|ACOUSTIC_MARK' })
Write-Output ("logcat 行数={0} 其中与 App/标记相关={1}" -f $lines.Count, $appLines.Count)

$pat = @{
    VAD    = '唤醒|VAD|vad|语音检测|开始说话|speech_detect|detect'
    Listen = 'listen start|已发送 listen start|listen\s*\{?\s*state'
    Stt    = 'stt|识别结果|语音识别|用户说|asr'
    Tts    = 'tts|播报|回复中|assistant|playAudio|AudioTrack'
    Error  = '未绑定|未配置|无智能体|连接失败|1005|ERROR|Exception'
}

# 按标记切窗口
$idx = 0
$windows = @{}
foreach ($l in $lines) {
    if ($l -match 'ACOUSTIC_MARK' -and $l -match 'RUN (\d+) START') { $idx = [int]$Matches[1]; $windows[$idx] = @{ Start = @(); End = @() } }
    elseif ($l -match 'ACOUSTIC_MARK' -and $l -match 'RUN (\d+) END') { if ($idx -gt 0) { $windows[$idx]['End'] += $l } }
    elseif ($idx -gt 0 -and $windows.ContainsKey($idx)) { $windows[$idx]['Start'] += $l }
}

$rows = @()
foreach ($i in 1..$Runs) {
    $w = $windows[$i]
    $body = if ($w) { @($w['Start'] | Where-Object { $_ -notmatch 'RUN \d+ END' }) } else { @() }
    $hit = @{}
    foreach ($k in $pat.Keys) { $hit[$k] = @($body | Where-Object { $_ -match $pat[$k] }).Count }
    $pass = ($hit['Stt'] -gt 0 -and $hit['Tts'] -gt 0)
    $rows += [pscustomobject]@{
        Run = $i; Lines = $body.Count
        VAD = $hit['VAD']; Listen = $hit['Listen']; Stt = $hit['Stt']; Tts = $hit['Tts']; Error = $hit['Error']
        Result = if ($pass) { 'PASS' } else { 'FAIL' }
    }
}

$rows | Format-Table -AutoSize
$rows | Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8

$passCount = @($rows | Where-Object Result -eq 'PASS').Count
Write-Output ("PASS {0}/{1}（阈值 {2}/{1}）" -f $passCount, $Runs, $MinPass)
Write-Output ("结论: " + $(if ($passCount -ge $MinPass) { 'PASS' } else { 'FAIL' }) + "  证据目录: $RunDir")

if ($Discover) {
    Write-Output "`n== Discover：与语音链路相关的原始行（供锁定正则）=="
    $appLines | Where-Object { $_ -match 'listen|stt|tts|vad|detect|唤醒|语音|识别|播报|AudioRecord|AudioTrack' } |
        ForEach-Object { ($_ -split "`t")[-1] } | Select-Object -Unique | Select-Object -First 80
}

if ($passCount -lt $MinPass) { exit 1 }
