$ErrorActionPreference = 'Continue'
$dev = '36c77fb6'
$out = 'C:\Users\Administrator\AppData\Local\Temp\zh-boundary'
$letters = 'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz'
$words = 'the quick brown fox jumps over the lazy dog and runs into the deep forest near the river bank today morning'
$cjkBase = '春江潮水连海平海上明月共潮生滟滟随波千万里何处春江无月明江流宛转绕芳甸月照花林皆似霰空里流霜不觉飞汀上白沙看不见'
$mixBase = '中A文B混C排D测E试F字G符H长I度J边K界L点M文N本O混P排Q测R试S字T符U混V排W测X试Y字Z符'
$emojiArr = @('😀','😃','😄','😁','😆','😅','🤣','😂','🙂','🙃','😉','😊','😇','🥰','😍')

$cases = @()
foreach ($n in 40,60,100) { $cases += @{ name = "abc$n"; text = $letters.Substring($n-34,$n) } }
foreach ($n in 34,50) { $cases += @{ name = "sp$n"; text = $words.Substring(0,$n) } }
$cases += @{ name = 'mix13'; text = $mixBase.Substring(0,13) }
$cases += @{ name = 'cjk16sp'; text = '春江 潮水 连海 平上 明月' }        # 16 汉字 + 4 空格
$cases += @{ name = 'cjk16pun'; text = '春江潮水连海平，海上明月共潮生。' }  # 16 汉字 + 2 标点
$cases += @{ name = 'cjk8en8'; text = '生活助手iPhone15' }                  # 8 汉字 + 8 ASCII

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
  $sttLines = ($raw | Select-String -Pattern '"type":"stt"' | Select-Object -First 2)
  $alert = ($raw | Select-String -Pattern '"type":"alert"' | Select-Object -First 1)
  $sttText = ''
  if ($sttLines) {
    $joined = ($sttLines | ForEach-Object { $_.ToString() }) -join "`n"
    if ($joined -match '收到消息: \{"type":"stt","text":"([^"]*)"') { $sttText = $Matches[1] }
  }
  $sttEcho = if ($sttText -eq $c.text) { 'yes' } elseif ($sttText) { 'diff' } else { 'no' }
  $verdict = if ($sttEcho -eq 'yes') { 'ACCEPT' } elseif ($alert) { 'REJECT' } elseif ($sttText) { 'ACCEPT-DIFF' } else { 'SILENT' }
  $injInfo = if ($inj) { ($inj.ToString() -replace '.*\[DEBUGINJECT\] 1/1 ', '') } else { 'NO-INJECT-LOG' }
  $summary += [pscustomobject]@{ name=$c.name; verdict=$verdict; stt=$sttEcho; alert=$(if($alert){'yes'}else{'no'}); inj=$injInfo }
  Write-Host ("[{0}] {1} stt={2} alert={3}" -f $c.name, $verdict, $sttEcho, $(if($alert){'yes'}else{'no'}))
}

$summary | Format-Table -AutoSize | Out-String -Width 300 | Tee-Object "$out\summary3.txt"
$summary | Export-Csv "$out\summary3.csv" -NoTypeInformation -Encoding UTF8
