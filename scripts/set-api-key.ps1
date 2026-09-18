#requires -Version 5.1
<#
  DeepSeek Harness：配置 API Key（支持一键粘贴）

  把 DeepSeek API Key 写入 <DSH_HOME>\.credentials.yaml。
  该文件是热加载的——保存后立即生效，无需重启 dsh。

  用法：双击「2-配置APIKey.bat」。推荐流程（一键粘贴，免手打）：
    1. 在 https://platform.deepseek.com 的「API Keys」页面用 Ctrl+C 复制你的 Key
    2. 双击本脚本，它会自动从剪贴板读取 Key，按【Enter】确认写入

  参数：
    -Key          非交互模式直接传 Key（脚本化使用）
    -HomeOverride 覆盖数据目录（默认读 DSH_HOME 环境变量）
#>
[CmdletBinding()]
param(
    [string]$Key = "",
    [string]$HomeOverride = ""
)

$ErrorActionPreference = 'Stop'

# ---------- 定位数据目录 ----------
$dshHome = $HomeOverride
if (-not $dshHome) { $dshHome = [Environment]::GetEnvironmentVariable('DSH_HOME', 'User') }
if (-not $dshHome) { $dshHome = $env:DSH_HOME }
if (-not $dshHome) { $dshHome = Join-Path $env:USERPROFILE 'DeepSeek Harness' }
$credsFile = Join-Path $dshHome '.credentials.yaml'

function Ask-YesNo([string]$question, [bool]$defaultYes) {
    $suffix = if ($defaultYes) { '[Y/n]' } else { '[y/N]' }
    $answer = Read-Host "$question $suffix"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $defaultYes }
    return $answer.Trim().ToLower() -in @('y', 'yes', '是', '1')
}

# 从剪贴板读取 API Key：提取 sk- 开头的 token（容忍剪贴板里混着网址/说明文字）
function Get-ClipboardKey {
    try {
        $raw = Get-Clipboard -Raw -ErrorAction Stop
        if (-not $raw) { return '' }
        $m = [regex]::Match($raw, 'sk-[A-Za-z0-9_\-]+')
        if ($m.Success) { return $m.Value }
        return ''
    } catch {
        return ''
    }
}

# 打码显示，避免完整 Key 出现在屏幕上
function Mask-Key([string]$k) {
    if ([string]::IsNullOrEmpty($k)) { return '' }
    if ($k.Length -le 8) { return $k }
    $head = [Math]::Min(8, $k.Length)
    $tail = [Math]::Min(4, $k.Length - $head)
    return $k.Substring(0, $head) + '…' + $k.Substring($k.Length - $tail)
}

Write-Host '==================================================' -ForegroundColor Magenta
Write-Host '   配置 DeepSeek API Key' -ForegroundColor Magenta
Write-Host '==================================================' -ForegroundColor Magenta

# ---------- 获取 Key ----------
# 优先：命令行传参（-Key）
$Key = $Key.Trim()

# 其次：自动从剪贴板一键粘贴
if (-not $Key) {
    $clipKey = Get-ClipboardKey
    if ($clipKey) {
        Write-Host ("    检测到剪贴板里的 API Key：{0}" -f (Mask-Key $clipKey)) -ForegroundColor Cyan
        if (Ask-YesNo '    使用剪贴板中的这个 Key ？（免手打，按回车即用）' $true) {
            $Key = $clipKey
        }
    }
}

# 若剪贴板还没有：引导复制后一键读取（免手打）
if (-not $Key) {
    Write-Host ''
    Write-Host '    ▌一键粘贴：' -ForegroundColor Cyan
    Write-Host '      1. 去 https://platform.deepseek.com 复制你的 API Key（Ctrl+C）' -ForegroundColor Cyan
    Write-Host '      2. 回到本窗口，按一次【Enter】，脚本会自动读取剪贴板，无需手打' -ForegroundColor Cyan
    $attempts = 0
    while (-not $Key -and $attempts -lt 3) {
        $attempts++
        $null = Read-Host '        已复制好？按【Enter】读取剪贴板'
        $clipKey = Get-ClipboardKey
        if ($clipKey) {
            Write-Host ("    已从剪贴板读取：{0}" -f (Mask-Key $clipKey)) -ForegroundColor Cyan
            $Key = $clipKey
        } else {
            Write-Host '        剪贴板里没找到 sk- 开头的 Key。' -ForegroundColor Yellow
        }
    }
}

# 仍没有：退回手动粘贴输入（兼容）
if (-not $Key) {
    Write-Host ''
    Write-Host '    （剪贴板读取三连失败，也可直接粘贴输入）' -ForegroundColor Yellow
    $secure = Read-Host '    请输入你的 DeepSeek API Key（输入不可见）' -AsSecureString
    if ($secure) {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { $Key = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($bstr) }
        finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
}

$Key = $Key.Trim()
if (-not $Key) {
    Write-Warn 'Key 为空，已取消。'
    exit 1
}
if ($Key -notlike 'sk-*') {
    Write-Host '    [!] 注意：DeepSeek API Key 一般以 sk- 开头，请确认没有粘错。' -ForegroundColor Yellow
}

# ---------- 写入（原子替换） ----------
if (-not (Test-Path $dshHome)) {
    New-Item -ItemType Directory -Path $dshHome -Force | Out-Null
}
$content = @"
# DeepSeek API Key（在 https://platform.deepseek.com 的 API Keys 页面创建）
# 本文件热加载：保存后立即生效，无需重启 dsh
DEEPSEEK_API_KEY: $Key
"@
$tmp = "$credsFile.tmp"
# 必须写「无 BOM」的 UTF-8，不能用 Set-Content -Encoding UTF8：
# Windows PowerShell 5.1 的 UTF8 会带 BOM。dsh 读到扁平旧格式后会迁移成
# `version: 1` + `refs:` 结构，迁移会把原有每行缩进两格——BOM 因此被挤到文档中间，
# 而 YAML 只剥离文档开头的 BOM，中间的 U+FEFF 是普通字符，会让注释行变成标量，
# 进而报 `BAD_INDENT at line 5, column 1`，dsh 直接起不来。
[System.IO.File]::WriteAllText($tmp, $content, (New-Object System.Text.UTF8Encoding($false)))
Move-Item -Path $tmp -Destination $credsFile -Force

Write-Host ''
Write-Host "    [OK] API Key 已保存到：$credsFile" -ForegroundColor Green
Write-Host '    现在可以双击「3-启动Web界面.bat」打开 Web 界面了。'
Write-Host '    （也可以直接在 Web 界面 Settings → Models 页面粘贴 Key）'
