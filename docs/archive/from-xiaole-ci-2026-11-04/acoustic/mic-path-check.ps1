# 声学回环 · 前置通路检查（不依赖云端 / 不依赖智能体）
#
# 目的：最坏情况下 70 装上后开发者授权或智能体配置又出问题，声学项就跑不了。
# 本检查只回答一个问题：**麦克风通路通不通**——权限是否真的授予、App 能否真的
# 开始录音（`dumpsys audio` 出现 `rec start/update`）。把云端因素彻底剥离。
#
# 用法：
#   powershell -File mic-path-check.ps1 -GrantMic -Runs 3
#   长按按钮方式（坐标取自 §4 按住说话截图）：
#   powershell -File mic-path-check.ps1 -GrantMic -Runs 3 -HoldXY "540,2250" -HoldMs 3000
#
# 判定：任一形式（VAD 或 长按）出现 App 录音行 ≥1 次 ⇒ 通路 OK。
# 注意：`pm grant` 是**测试手段**，不是产品行为；产品必须自己申请权限。

param(
    [string]$Serial   = $env:ADB_SERIAL,
    [string]$Wav      = 'speech-zh-g90.wav',
    [int]$Runs        = 3,
    [int]$IntervalSec = 5,
    [string]$HoldXY   = '',
    [int]$HoldMs      = 3000,
    [switch]$GrantMic,
    [string]$OutDir   = (Join-Path $PSScriptRoot 'runs')
)

$ErrorActionPreference = 'Stop'
$WavPath = if (Test-Path $Wav) { (Resolve-Path $Wav).Path } else { Join-Path $PSScriptRoot $Wav }
if (-not (Test-Path $WavPath)) { throw "音源不存在: $WavPath" }
$Pkg = 'com.zcstudy.xiaole'
$RunDir = Join-Path $OutDir ("{0}-micpath" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

function AudioDump([string]$p) { adb -s $Serial shell dumpsys audio > $p }
function Shot([string]$p) { adb -s $Serial shell screencap -p "/sdcard/_mp.png" | Out-Null; adb -s $Serial pull "/sdcard/_mp.png" $p | Out-Null; adb -s $Serial shell rm "/sdcard/_mp.png" | Out-Null }

# ---------- 0. 前置 ----------
$pkgLine = (adb -s $Serial shell dumpsys package $Pkg | Select-String 'versionCode=' | Select-Object -First 1).Line.Trim()
$fg  = (adb -s $Serial shell dumpsys activity activities | Select-String 'mResumedActivity' | Select-Object -First 1).Line.Trim()
$mic = (adb -s $Serial shell appops get $Pkg RECORD_AUDIO).Trim()
Write-Output "设备: $Serial | $pkgLine"
Write-Output "前台: $fg"
Write-Output "麦克风: $mic"

if ($GrantMic) {
    # 本机 pm grant 被 ColorOS 拒绝（GRANT_RUNTIME_PERMISSIONS），改走 UI 授权
    Write-Output "pm grant 在本机不可用，改走 grant-mic-ui.ps1（UI 通道）"
    & (Join-Path $PSScriptRoot 'grant-mic-ui.ps1') -Serial $Serial
    $mic = (adb -s $Serial shell appops get $Pkg RECORD_AUDIO).Trim()
    Write-Output "授权后 => $mic"
}
$permOk = ($mic -notmatch 'ignore')
Write-Output "权限判定: $(if($permOk){'GRANTED'}else{'DENIED'})"

if ($fg -notmatch 'com\.zcstudy\.xiaole') {
    adb -s $Serial shell am start -n $Pkg/.MainActivity | Out-Null
    Start-Sleep -Seconds 4
}

# ---------- 1. 基线 ----------
AudioDump (Join-Path $RunDir 'audio-run0.txt')
Shot (Join-Path $RunDir 'shot-0.png')

$player = New-Object Media.SoundPlayer $WavPath
$rows = @()

# ---------- 2. 逐次检查 ----------
for ($i = 1; $i -le $Runs; $i++) {
    Write-Output ("[{0}] 检查 {1}/{2}" -f (Get-Date -Format 'HH:mm:ss'), $i, $Runs)
    if ($HoldXY) {
        # 长按说话（cloud-free），松手后等一会儿再取证据
        adb -s $Serial shell input swipe ($HoldXY -split ',')[0] ($HoldXY -split ',')[1] ($HoldXY -split ',')[0] ($HoldXY -split ',')[1] $HoldMs | Out-Null
        Start-Sleep -Seconds 3
    } else {
        $player.PlaySync()
    }
    Start-Sleep -Seconds $IntervalSec
    AudioDump (Join-Path $RunDir ("audio-run{0}.txt" -f $i))
    Shot (Join-Path $RunDir ("shot-{0}.png" -f $i))

    $prev = Get-Content (Join-Path $RunDir ("audio-run{0}.txt" -f ($i - 1))) -Encoding UTF8 -ErrorAction SilentlyContinue
    $cur  = Get-Content (Join-Path $RunDir ("audio-run{0}.txt" -f $i)) -Encoding UTF8 -ErrorAction SilentlyContinue
    $new  = $cur | Where-Object { $prev -notcontains $_ }
    $rec  = @($new | Where-Object { $_ -match "pack:$Pkg" -and $_ -match 'rec (start|update)|recording' }).Count
    $rows += [pscustomobject]@{ Run = $i; AppRec = $rec; Mode = $(if($HoldXY){'longpress'}else{'vad'}) }
}

$rows | Format-Table -AutoSize
$rows | Export-Csv -Path (Join-Path $RunDir 'summary.csv') -NoTypeInformation -Encoding UTF8

$recTotal = @($rows | Where-Object { $_.AppRec -gt 0 }).Count
Write-Output ("出现 App 录音的轮次: {0}/{1}" -f $recTotal, $Runs)

if ($permOk -and $recTotal -ge 1) {
    Write-Output "前置通路检查: PASS（权限已授予 + App 真的开始录音，云端因素已剥离）  证据: $RunDir"
    exit 0
}

Write-Output "前置通路检查: FAIL"
if (-not $permOk) { Write-Output "  归因① 权限仍是 ignore：先 -GrantMic，或到设置里手动授予" }
elseif ($recTotal -eq 0) {
    Write-Output "  归因② 权限已给但 App 未开始录音："
    Write-Output "        - 若用 VAD 方式：当前页面可能不是语音/聊天页（无智能体时不会进听音态），改用 -HoldXY 长按按钮"
    Write-Output "        - 若用长按方式：坐标不对或按钮不可用；先从 §4 截图取真实坐标"
    Write-Output "        - 另查 Mika 是否占着麦克风：dumpsys audio 里是否有 com.wangzan101.mika 的 rec start 未释放"
}
exit 1
