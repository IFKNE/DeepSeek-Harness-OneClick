$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\scripts\lib\InstallerCommon.psm1') -Force
function Assert-Equal($actual, $expected) { if ($actual -ne $expected) { throw "Expected '$expected', got '$actual'" } }
function Assert-True($value) { if (-not $value) { throw 'Expected true.' } }
$paths = Get-DshInstallPaths -LocalAppData 'C:\Users\Test\AppData\Local' -UserProfile 'C:\Users\Test'
Assert-Equal $paths.LauncherRoot 'C:\Users\Test\AppData\Local\Programs\DeepSeek Harness'
Assert-Equal $paths.DataRoot 'C:\Users\Test\DeepSeek Harness'
Assert-Equal (ConvertTo-DshRedactedText 'http://127.0.0.1:3080/?token=abc') 'http://127.0.0.1:3080/?token=<redacted>'
Assert-True ((ConvertTo-DshRedactedText 'Bearer sk-secret') -notmatch 'sk-secret')
$badManifest = Join-Path $env:TEMP ('dsh-bad-manifest-' + [Guid]::NewGuid().ToString('N') + '.json')
[IO.File]::WriteAllText($badManifest, '{"dataRoot":"C:\Users\Test\DeepSeek Harness"}', [Text.UTF8Encoding]::new($false))
$repaired = Read-InstallerManifest $badManifest
if ($null -eq $repaired) { throw 'Manifest repair returned null.' }
Assert-Equal $repaired.dataRoot 'C:\Users\Test\DeepSeek Harness'
Remove-Item -LiteralPath $badManifest -Force
Write-Output 'InstallerCommon tests passed.'
