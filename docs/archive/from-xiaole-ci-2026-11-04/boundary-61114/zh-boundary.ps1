$ErrorActionPreference = 'Continue'
$dev = '36c77fb6'
$out = '<TEMP>\zh-boundary'
New-Item -ItemType Directory -Force $out | Out-Null

$cjkBase = '春江潮水连海平海上明月共潮生滟滟随波千万里何处春江无月明江流宛转绕芳甸月照花林皆似霰空里流霜不觉飞汀上白沙看不见'
$emojiArr = @('😀','😃','😄','😁','😆','😅','🤣','😂','🙂','🙃','😉','😊','😇','🥰','😍','🤩','😘','😗','😚','😙','🥲','😋','😛','😜','🤪','😝','🤑','🤗','🤭','🤫','🤔','🤐','🤨','😐','😑','😶','😏','😒','🙄','😬')
$mixBase = '中A文B混C排D测E试F字G符H长I度J边K界L点M文N本O混P排Q测R试S字T符U混V排W测X试Y字Z符'

$cases = @()
foreach ($n in 11,16,20,25,30,33,34,40) { $cases += @{ name = "cjk$n"; text = $cjkBase.Substring(0,$n); group = 'cjk' } }
foreach ($n in 8,9,11,16,33,34) { $cases += @{ name = "emo$n"; text = ($emojiArr[0..($n-1)] -join ''); group = 'emoji' } }
foreach ($n in 20,33,34,40) { $cases += @{ name = "mix$n"; text = $mixBase.Substring(0,$n); group = 'mix' } }

$summary = @()
foreach ($c in $cases) {
  adb -s $dev shell am force-stop com.zcstudy.xiaole | Out-Null
  adb -s $dev logcat -c | Out-Null
  adb -s $dev shell am start -n com.zcstudy.xiaole/.MainActivity -e debug_send_text $c.text | Out-Null
  Start-Sleep -Seconds 4
  adb -s $dev shell input tap 470 390 | Out-Null
  Start-Sleep -Seconds 14
  $raw = adb -s $dev logcat -d -s flutter
  $raw | Set-Content "$out\$($c.name).log" -Encoding UTF8

  $inj = ($raw | Select-String -Pattern '\[DEBUGINJECT\] 1/1' | Select-Object -First 1)
  $sttLines = ($raw | Select-String -Pattern '"type":"stt"' | Select-Object -First 3)
  $alert = ($raw | Select-String -Pattern '"type":"alert"' | Select-Object -First 1)
  $tts = (($raw | Select-String -Pattern '"state":"start"') | Measure-Object).Count

  $sttEcho = 'no'
  $sttText = ''
  if ($sttLines) {
    $joined = ($sttLines | ForEach-Object { $_.ToString() }) -join "`n"
    if ($joined -match '收到消息: \{"type":"stt","text":"([^"]*)"') { $sttText = $Matches[1] }
    if ($sttText -eq $c.text) { $sttEcho = 'yes' } elseif ($sttText) { $sttEcho = 'diff' }
  }
  $verdict = if ($sttEcho -eq 'yes') { 'ACCEPT' } elseif ($alert) { 'REJECT' } else { 'SILENT' }
  $summary += [pscustomobject]@{
    name = $c.name; group = $c.group; verdict = $verdict; stt = $sttEcho
    alert = $(if($alert){'yes'}else{'no'}); tts = $tts; sttText = $sttText
  }
  Write-Host ("[{0}] {1} stt={2} alert={3} tts={4}" -f $c.name, $verdict, $sttEcho, $(if($alert){'yes'}else{'no'}), $tts)
}

$summary | Format-Table -AutoSize | Out-String -Width 260 | Tee-Object "$out\summary.txt"
$summary | Export-Csv "$out\summary.csv" -NoTypeInformation -Encoding UTF8
