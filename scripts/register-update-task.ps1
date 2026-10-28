#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$DataRoot = (Join-Path $env:USERPROFILE 'DeepSeek Harness'),
    [string]$ScriptRoot = $PSScriptRoot
)
$ErrorActionPreference = 'Stop'
$taskName = 'DeepSeek Harness Daily Update Check'
$script = Join-Path $ScriptRoot 'update.ps1'
if (-not (Test-Path -LiteralPath $script)) { throw "找不到更新脚本：$script" }
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`" -CheckOnly -Scheduled -DataRoot `"$DataRoot`""
$trigger = New-ScheduledTaskTrigger -Daily -At 10:00
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
Write-Output "已注册每日更新检查：$taskName"
