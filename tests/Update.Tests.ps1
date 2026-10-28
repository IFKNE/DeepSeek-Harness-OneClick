$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot '..\scripts\update.ps1'
$tokens = $null; $errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($script,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors) { throw ($errors | Out-String) }
if ((Get-Content -LiteralPath $script -Raw) -notmatch 'AssumeNo') { throw 'Update script lacks explicit decline path.' }
Write-Output 'Update script safety test passed.'
