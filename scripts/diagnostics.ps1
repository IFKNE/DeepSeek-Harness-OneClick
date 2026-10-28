#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputRoot = (Join-Path (Join-Path $env:USERPROFILE 'DeepSeek Harness') 'diagnostics'))
$ErrorActionPreference = 'Stop'
$dshHome = Join-Path $env:USERPROFILE 'DeepSeek Harness'
$report = Join-Path $OutputRoot ("dsh-diagnostics-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
Import-Module (Join-Path $PSScriptRoot 'lib\InstallerCommon.psm1') -Force
$lines = @("DeepSeek Harness diagnostics", "Generated: $(Get-Date -Format o)", "OS: $([Environment]::OSVersion.Version)")
try { $lines += "Node: $((& node --version 2>$null) -join '')" } catch { $lines += 'Node: unavailable' }
try { $lines += "DSH: $((& (Join-Path $env:APPDATA 'npm\dsh.cmd') --version 2>$null) -join '')" } catch { $lines += 'DSH: unavailable' }
$lines += "DSH_HOME: $dshHome", "Port3080Listening: $(Get-DshListener -Port 3080)"
$log = Get-ChildItem -LiteralPath (Join-Path $dshHome 'launcher\logs') -Filter '*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($log) { $lines += '--- recent log ---'; $lines += @(Get-Content -LiteralPath $log.FullName -Tail 60 | ForEach-Object { ConvertTo-DshRedactedText $_ }) }
[IO.File]::WriteAllLines($report, $lines, [Text.UTF8Encoding]::new($false))
Write-Host "诊断报告已生成：$report" -ForegroundColor Green
