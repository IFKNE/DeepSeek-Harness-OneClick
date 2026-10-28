#requires -Version 5.1
[CmdletBinding()]
param([string]$InstallRoot = "")
$ErrorActionPreference = 'Stop'
$root = if ($InstallRoot) { $InstallRoot } else { Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness' }
$exe = Join-Path $root 'DeepSeek Harness.exe'
if (-not (Test-Path -LiteralPath $exe)) {
    Write-Host '未找到原生启动器，请先运行「1-一键安装.bat」或「7-修复安装.bat」。' -ForegroundColor Yellow
    exit 1
}
Start-Process -FilePath $exe -WorkingDirectory $root
