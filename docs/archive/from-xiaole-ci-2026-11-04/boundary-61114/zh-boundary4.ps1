$ErrorActionPreference = 'Continue'
$dev = '36c77fb6'
$out = 'C:\Users\Administrator\AppData\Local\Temp\zh-boundary'
$cjk = '春江潮水连海平海上明月共潮生滟滟随波千万里何处春江无月明'

$cases = @(
  @{ name='cjk14p'; text = $cjk.Substring(0,14) + '，' },
  @{ name='cjk15p'; text = $cjk.Substring(0,15) + '，' },
  @{ name='cjk16p'; text = $cjk.Substring(0,16) + '，' },
  @{ name='real15'; text = '帮我查下iPhone15多少钱' },
  @{ name='real11'; text = '帮我看下iPhone价格' },
  @{ name='real12a'; text = '今天天气怎么样适合出门' }
)

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
  Write-Host ("[{0}] {1} stt={2}" -f $c.name, $verdict, $sttEcho)
}

$summary | Format-Table -AutoSize | Out-String -Width 300 | Tee-Object "$out\summary4.txt"
$summary | Export-Csv "$out\summary4.csv" -NoTypeInformation -Encoding UTF8
