# 声学回环验证 · 音源生成（Windows SAPI / 中文 Huihui）
# 用法：powershell -File tts-gen.ps1
# 产出：speech-zh.wav（原声） + speech-zh-g50/g70/g90.wav（按振幅缩放的"音量档位"）
# 说明：不改电脑系统音量，音量档位用 wav 增益实现（可复现、不污染桌面设置）。

param(
    [string]$OutDir = $PSScriptRoot,
    [string]$Text   = "小乐，帮我查一下今天北京的天气怎么样，出门要不要带伞；顺便看看明天上午有没有雨，我要去城东的维修点取一下修好的笔记本电脑。",
    [int]$Rate      = -1,     # -10..10，-1 略慢，接近自然口语
    [int]$Volume    = 100
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

$base = Join-Path $OutDir 'speech-zh.wav'
if (Test-Path $base) { Remove-Item $base -Force }

$voice = New-Object -ComObject SAPI.SpVoice
$voice.Voice = $voice.GetVoices().Item(0)   # Microsoft Huihui Desktop - Chinese (Simplified)
$voice.Rate = $Rate
$voice.Volume = $Volume

$fs = New-Object -ComObject SAPI.SpFileStream
$format = New-Object -ComObject SAPI.SpAudioFormat
$format.Type = 22   # SAFT22kHz16BitMono
$fs.Format = $format
# SSFMCreateForWrite = 3
$null = $fs.Open($base, 3, $false)
$voice.AudioOutputStream = $fs
$voice.Speak($Text) | Out-Null
$fs.Close()

function Get-WavInfo([string]$p) {
    $b = [IO.File]::ReadAllBytes($p)
    $pos = 12; $fmt = $null; $dataOff = -1; $dataLen = 0
    while ($pos -lt $b.Length - 4) {
        $id = [Text.Encoding]::ASCII.GetString($b, $pos, 4)
        $sz = [BitConverter]::ToInt32($b, $pos + 4)
        if ($id -eq 'fmt ') { $fmt = $pos + 8 }
        if ($id -eq 'data') { $dataOff = $pos + 8; $dataLen = $sz; break }
        $pos += 8 + $sz + ($sz % 2)
    }
    $byteRate = [BitConverter]::ToInt32($b, $fmt + 8)
    $bits = [BitConverter]::ToInt16($b, $fmt + 14)
    [pscustomobject]@{ Bytes = $b.Length; DataOffset = $dataOff; DataLen = $dataLen; ByteRate = $byteRate; Bits = $bits;
        Seconds = [math]::Round($dataLen / $byteRate, 2) }
}

function New-GainWav([string]$src, [string]$dst, [double]$gain) {
    $b = [IO.File]::ReadAllBytes($src)
    $info = Get-WavInfo $src
    for ($i = $info.DataOffset; $i -lt $info.DataOffset + $info.DataLen - 1; $i += 2) {
        $s = [BitConverter]::ToInt16($b, $i)
        $n = [int][math]::Round($s * $gain)
        if ($n -gt 32767) { $n = 32767 } elseif ($n -lt -32768) { $n = -32768 }
        $b[$i] = [byte]($n -band 0xFF)
        $b[$i + 1] = [byte](($n -shr 8) -band 0xFF)
    }
    [IO.File]::WriteAllBytes($dst, $b)
}

$i = Get-WavInfo $base
foreach ($g in @(0.5, 0.7, 0.9)) {
    New-GainWav $base (Join-Path $OutDir ("speech-zh-g{0}.wav" -f [int]($g * 100)) ) $g
}

Get-ChildItem $OutDir -Filter 'speech-zh*.wav' | ForEach-Object {
    $w = Get-WavInfo $_.FullName
    [pscustomobject]@{ File = $_.Name; KB = [math]::Round($_.Length / 1KB, 1); Seconds = $w.Seconds; Bits = $w.Bits; ByteRate = $w.ByteRate }
} | Format-Table -AutoSize

Write-Output ("ZH_TEXT=" + $Text)
Write-Output ("DURATION_SEC=" + $i.Seconds)
