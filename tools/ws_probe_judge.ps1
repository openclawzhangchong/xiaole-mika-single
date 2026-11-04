# 用途：判定 ⑤stop / ⑥pair / ⑥'mcp 候选"是否有效保活且零副作用"。
#   用法：powershell -File tools/ws_probe_judge.ps1 -LogPath <logcat.txt> -Mode stop [-AudioTrackLog <full.txt>]
#   条件：① 首个 tick 后 180s 内未出现 "停止（服务器断开 code=1005）"；② 零 stt/tts/llm/binary 下行。
#   注意：logcat 需包含 flutter 的 [PROBE] 行；AudioTrack 检查需提供完整 logcat。
param(
  [Parameter(Mandatory = $true)][string]$LogPath,
  [Parameter(Mandatory = $true)][ValidateSet('detect', 'stop', 'pair', 'mcp')][string]$Mode,
  [string]$AudioTrackLog = '',
  [int]$HoldSec = 180
)

if (-not (Test-Path $LogPath)) { Write-Error "找不到日志: $LogPath"; exit 2 }
$lines = Get-Content $LogPath

$ticks      = @($lines | Where-Object { $_ -match '\[PROBE\] tick mode=' + $Mode })
$stt        = @($lines | Where-Object { $_ -match '\[PROBE\] 下行.*type=stt' }).Count
$tts        = @($lines | Where-Object { $_ -match '\[PROBE\] 下行.*type=tts' }).Count
$llm        = @($lines | Where-Object { $_ -match '\[PROBE\] 下行.*type=llm' }).Count
$binary     = @($lines | Where-Object { $_ -match '\[PROBE\] 下行.*type=binary' }).Count
$stopProbe  = @($lines | Where-Object { $_ -match '\[PROBE\] 停止（服务器断开' })
$close1005  = @($lines | Where-Object { $_ -match '\[PROBE\] 停止.*code=1005' })
$audioStarts = 0
if ($AudioTrackLog -and (Test-Path $AudioTrackLog)) {
  $audioStarts = @(Select-String -Path $AudioTrackLog -Pattern 'AudioTrack.*start' | Where-Object { $_.Line -match '29296' }).Count
}

$tickCount = $ticks.Count
$hasTicks  = $tickCount -gt 0
$sideEffect = ($stt + $tts + $llm + $binary + $audioStarts) -gt 0
$reclaimedEarly = $close1005.Count -gt 0

Write-Output "候选=$Mode tick=$tickCount stt=$stt tts=$tts llm=$llm binary=$binary AudioTrack.start=$audioStarts"
if (-not $hasTicks) { Write-Output "判定=无法判定（没有 $Mode 的 tick 记录，确认探针已切到该候选）"; exit 1 }
if ($sideEffect) {
  Write-Output "判定=有效但有副作用（与 detect 同罪，不得默认开启）"
  exit 1
}
if ($reclaimedEarly) {
  Write-Output "判定=FAIL（$HoldSec s 内被 1005 回收）"
  exit 1
}
Write-Output "判定=PASS（${HoldSec}s+ 无 1005 且零副作用）"
