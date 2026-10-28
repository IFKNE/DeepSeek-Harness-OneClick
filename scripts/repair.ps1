#requires -Version 5.1
[CmdletBinding()]
param([switch]$AssumeYes)
$ErrorActionPreference = 'Stop'
$install = Join-Path $PSScriptRoot 'install.ps1'
& powershell -NoProfile -ExecutionPolicy Bypass -File $install -AssumeYes:$AssumeYes -NoNodeInstall -NoDshInstall
Write-Host '修复完成：已重新部署启动器、快捷方式和每日检查。' -ForegroundColor Green
