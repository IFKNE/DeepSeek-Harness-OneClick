$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceRoot = Join-Path $projectRoot 'src'
$testRoot = Join-Path $projectRoot 'tests'
$binRoot = Join-Path $projectRoot 'bin'
$iconPath = Join-Path $projectRoot 'assets\DeepSeekHarness.ico'
$compiler = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'

New-Item -ItemType Directory -Path $binRoot -Force | Out-Null

$testExecutable = Join-Path $binRoot 'LauncherCoreTests.exe'
$launcherExecutable = Join-Path $binRoot 'DeepSeek Harness.exe'

& $compiler /nologo /warnaserror+ /t:exe "/out:$testExecutable" `
    (Join-Path $sourceRoot 'LauncherCore.cs') `
    (Join-Path $testRoot 'LauncherCoreTests.cs')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $testExecutable
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $compiler /nologo /warnaserror+ /t:winexe /platform:anycpu `
    /r:System.Windows.Forms.dll `
    "/win32icon:$iconPath" `
    "/out:$launcherExecutable" `
    (Join-Path $sourceRoot 'LauncherCore.cs') `
    (Join-Path $sourceRoot 'Program.cs')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Get-Item -LiteralPath $launcherExecutable |
    Select-Object FullName, Length, LastWriteTime
