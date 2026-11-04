# 麦克风权限 · UI 授权（ColorOS 专用）
#
# 背景（2026-11-05 实测）：本机 `pm grant` 与 `appops set` 都被系统拒绝：
#   - pm grant → SecurityException: Neither user 2000 nor current process has GRANT_RUNTIME_PERMISSIONS
#   - appops set → SecurityException: uid 2000 does not have MANAGE_APP_OPS_MODES
# 也就是说**不存在 adb 授权通道**，只能走 UI。产品行为必须是 App 自己申请（首次进语音页弹窗），
# 本脚本只用于验收兜底：App 弹窗没出现时，从系统设置里补授。
#
# 用法：
#   powershell -File grant-mic-ui.ps1 -DryRun    # 只定位不点确认，打印各页坐标
#   powershell -File grant-mic-ui.ps1            # 真正授予并校验 appops

param([string]$Serial = $env:ADB_SERIAL, [switch]$DryRun)
$ErrorActionPreference = 'Stop'
$Pkg = 'com.zcstudy.xiaole'

function DumpUi {
    adb -s $Serial shell uiautomator dump /sdcard/ui.xml 2>$null | Out-Null
    Start-Sleep -Milliseconds 600
    (adb -s $Serial shell cat /sdcard/ui.xml) -join ''
}

# 返回所有节点：文本 + 可点击 + 中心坐标
function Nodes([string]$xml) {
    $out = @()
    foreach ($m in [regex]::Matches($xml, '<node[^>]+>')) {
        $tag = $m.Value
        $t = if ($tag -match 'text="([^"]*)"') { $Matches[1] } else { '' }
        $b = if ($tag -match 'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"') {
            [pscustomobject]@{ X = ([int]$Matches[1] + [int]$Matches[3]) / 2; Y = ([int]$Matches[2] + [int]$Matches[4]) / 2 }
        } else { $null }
        $c = if ($tag -match 'clickable="true"') { $true } else { $false }
        if ($t -ne '' -and $b) { $out += [pscustomobject]@{ Text = $t; Clickable = $c; X = [int]$b.X; Y = [int]$b.Y } }
    }
    $out
}

function TapNode($n, [string]$what, [switch]$Nav) {
    if (-not $n) { throw "未找到节点：$what" }
    # -Nav：纯导航点击，即使 DryRun 也照点（只翻页，不改权限）；最终"允许"始终受 DryRun 保护
    if ($DryRun -and -not $Nav) { Write-Output ("  [DRY] 命中 '$($n.Text)' @ ($($n.X),$($n.Y)) clickable=$($n.Clickable)，未点") ; return }
    adb -s $Serial shell input tap $n.X $n.Y | Out-Null
    Start-Sleep -Seconds 2
}

function FindText($nodes, [string]$pat) { $nodes | Where-Object { $_.Text -match $pat } | Select-Object -First 1 }

# ---------- 0. 现状 ----------
$mic = (adb -s $Serial shell appops get $Pkg RECORD_AUDIO).Trim()
Write-Output "当前: $mic"
if ($mic -notmatch 'ignore') { Write-Output "已授予，无需操作"; exit 0 }

# ---------- 1. 应用详情 → 权限 ----------
adb -s $Serial shell am start -a android.settings.APPLICATION_DETAILS_SETTINGS -d "package:$Pkg" | Out-Null
Start-Sleep -Seconds 2
$n = DumpUi
$p = FindText (Nodes $n) '权限|Permissions'
TapNode $p '应用详情·权限入口' -Nav

# ---------- 2. 麦克风 ----------
$n = DumpUi
$m = FindText (Nodes $n) '麦克风|Microphone|录音'
if (-not $m) { Write-Output "页面文本抽样："; (Nodes $n | Select-Object -First 30 | ForEach-Object { $_.Text }) -join ' | ' }
TapNode $m '权限列表·麦克风' -Nav

# ---------- 3. 允许 ----------
$n = DumpUi
$allow = FindText (Nodes $n) '仅在使用中允许|使用时允许|仅在使用该应用时允许|允许|Allow'
TapNode $allow '麦克风·允许'

# ---------- 4. 校验 ----------
Start-Sleep -Seconds 1
$mic2 = (adb -s $Serial shell appops get $Pkg RECORD_AUDIO).Trim()
Write-Output "结果: $mic2"
if ($DryRun) { Write-Output "DRY RUN 完成（未点确认）；如坐标符合预期，去掉 -DryRun 再跑。" ; exit 0 }
if ($mic2 -match 'ignore') { Write-Output "仍为 ignore：请人工在 设置→应用→权限→麦克风 里授予，并回报页面文本"; exit 1 }
Write-Output "麦克风已授予（UI 通道）"
