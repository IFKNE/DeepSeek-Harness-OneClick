#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Scheduled,
    [switch]$AssumeYes,
    [switch]$AssumeNo,
    [string]$DataRoot = (Join-Path $env:USERPROFILE 'DeepSeek Harness')
)
$ErrorActionPreference = 'Stop'
$common = Join-Path $PSScriptRoot 'lib\InstallerCommon.psm1'
Import-Module $common -Force
$manifestPath = Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness\installer-manifest.json'
$manifest = Read-InstallerManifest $manifestPath
$log = Join-Path $DataRoot 'installer-logs\update.log'
$api = 'https://api.github.com/repos/IFKNE/DeepSeek-Harness-OneClick/releases/latest'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $release = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'DeepSeek-Harness-Updater' } -TimeoutSec 12
} catch {
    Write-DshLog "更新元数据暂不可用，保持现有安装：$($_.Exception.Message)" $log
    if (-not $Scheduled) { Write-Host '暂时无法检查更新，当前安装仍可正常使用。' -ForegroundColor Yellow }
    exit 0
}
$remote = [string]$release.tag_name
$local = if ($manifest) { [string]$manifest.installerVersion } else { '0.0.0' }
if (-not $remote -or $remote.TrimStart('v') -eq $local.TrimStart('v')) {
    Write-DshLog "无可用更新：当前=$local" $log
    if (-not $Scheduled) { Write-Host "当前已是最新安装包（$local）。" -ForegroundColor Green }
    exit 0
}
if ($CheckOnly -or $Scheduled) {
    if ($Scheduled) { Write-DshLog "发现新版本 $remote；等待用户手动确认安装" $log; exit 0 }
    Write-Host "发现新版本 $remote（当前 $local）。请重新下载最新版安装包后运行安装。" -ForegroundColor Cyan
    exit 0
}
if ($AssumeNo) { Write-DshLog "用户跳过更新：$remote" $log; exit 0 }
if (-not $AssumeYes) {
    $answer = Read-Host "发现新版本 $remote，是否现在下载并安装？ [y/N]"
    if ($answer.Trim().ToLower() -notin @('y','yes','是','1')) { Write-DshLog "用户跳过更新：$remote" $log; exit 0 }
}
$asset = @($release.assets | Where-Object { $_.name -match '\.(zip|exe)$' } | Select-Object -First 1)
if (-not $asset) { Write-DshLog "发布未提供可下载安装包：$remote" $log; Write-Host '发布未提供可下载的安装包，请手动下载。' -ForegroundColor Yellow; exit 1 }
$tmp = Join-Path $env:TEMP ("dsh-update-" + [Guid]::NewGuid().ToString('N') + '.zip')
try {
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmp -UseBasicParsing -TimeoutSec 120
    if ($asset.digest -and $asset.digest -match '^sha256:([0-9a-fA-F]+)$') {
        $actual = Get-FileSha256 $tmp
        if ($actual -ne $Matches[1].ToLowerInvariant()) { throw '更新包 SHA-256 校验失败。' }
    }
    Write-DshLog "更新包已校验，需手动解压并运行最新版安装器：$remote" $log
    Write-Host "更新包已下载到：$tmp`n请解压后运行新的「1-一键安装.bat」完成更新。" -ForegroundColor Green
} catch {
    Write-DshLog "更新失败：$($_.Exception.Message)" $log
    Write-Host "更新失败：$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
