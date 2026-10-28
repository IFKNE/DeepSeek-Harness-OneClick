$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$required = @(
    '1-一键安装.bat','2-配置APIKey.bat','3-启动Web界面.bat','4-卸载.bat','6-检查更新.bat','7-修复安装.bat','8-生成诊断报告.bat',
    'installer-manifest.json','launcher\bin\DeepSeek Harness.exe','launcher\assets\DeepSeekHarness.ico',
    'scripts\install.ps1','scripts\launch.ps1','scripts\update.ps1','scripts\repair.ps1','scripts\diagnostics.ps1','scripts\uninstall.ps1',
    'scripts\lib\InstallerCommon.psm1'
)
foreach ($item in $required) { if (-not (Test-Path -LiteralPath (Join-Path $root $item))) { throw "Missing package entry: $item" } }
foreach ($forbidden in @('DeepSeek Harness\sessions','profiles\web\.credentials.yaml','edge-icon-profile')) { if (Test-Path -LiteralPath (Join-Path $root $forbidden)) { throw "Forbidden generated data is packaged: $forbidden" } }
Write-Output 'Package smoke test passed.'
