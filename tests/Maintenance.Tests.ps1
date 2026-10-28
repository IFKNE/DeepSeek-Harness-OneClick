$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
foreach ($script in @('repair.ps1','diagnostics.ps1','uninstall.ps1')) {
    $path = Join-Path $root "scripts\$script"
    $tokens = $null; $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors) | Out-Null
    if ($errors) { throw "$script syntax error: $($errors | Out-String)" }
}
if ((Get-Content -LiteralPath (Join-Path $root 'scripts\uninstall.ps1') -Raw) -notmatch 'RemoveData') { throw 'Uninstall lacks explicit data-removal switch.' }
Write-Output 'Maintenance script safety test passed.'
