#requires -Version 5.1
<#
  DeepSeek Harness：配置 API Key

  把 DeepSeek API Key 写入 <DSH_HOME>\.credentials.yaml。
  该文件是热加载的——保存后立即生效，无需重启 dsh。

  用法：双击「2-配置APIKey.bat」，按提示粘贴 Key（输入时不可见）。
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

Write-Host '==================================================' -ForegroundColor Magenta
Write-Host '   配置 DeepSeek API Key' -ForegroundColor Magenta
Write-Host '==================================================' -ForegroundColor Magenta

# ---------- 获取 Key ----------
if (-not $Key) {
    $secure = Read-Host '请输入你的 DeepSeek API Key（输入时不可见）' -AsSecureString
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
Set-Content -Path $tmp -Value $content -Encoding UTF8
Move-Item -Path $tmp -Destination $credsFile -Force

Write-Host ''
Write-Host "    [OK] API Key 已保存到：$credsFile" -ForegroundColor Green
Write-Host '    现在可以双击「3-启动Web界面.bat」打开 Web 界面了。'
Write-Host '    （也可以直接在 Web 界面 Settings → Models 页面粘贴 Key）'
