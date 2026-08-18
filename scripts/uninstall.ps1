#requires -Version 5.1
<#
  DeepSeek Harness：卸载

  依次：删除开机自启 → 删除 DSH_HOME 环境变量 → （询问）删除数据目录 → （询问）卸载全局包
  用法：双击「4-卸载.bat」
  参数：
    -Yes  跳过所有确认（自动化使用）
#>
[CmdletBinding()]
param([switch]$Yes)

$ErrorActionPreference = 'Stop'

function Ask-YesNo([string]$question, [bool]$defaultYes) {
    if ($Yes) { return $defaultYes }
    $suffix = if ($defaultYes) { '[Y/n]' } else { '[y/N]' }
    $answer = Read-Host "$question $suffix"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $defaultYes }
    return $answer.Trim().ToLower() -in @('y', 'yes', '是', '1')
}

Write-Host '==================================================' -ForegroundColor Magenta
Write-Host '   卸载 DeepSeek Harness' -ForegroundColor Magenta
Write-Host '==================================================' -ForegroundColor Magenta

# 1. 开机自启
$startupDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
$vbsPath = Join-Path $startupDir 'dsh-web-autostart.vbs'
if (Test-Path $vbsPath) {
    Remove-Item $vbsPath -Force
    Write-Host '    [OK] 已删除开机自启' -ForegroundColor Green
} else {
    Write-Host '    无开机自启配置，跳过'
}

# 2. DSH_HOME 环境变量
$dshHome = [Environment]::GetEnvironmentVariable('DSH_HOME', 'User')
if ($dshHome) {
    [Environment]::SetEnvironmentVariable('DSH_HOME', $null, 'User')
    Write-Host "    [OK] 已删除用户环境变量 DSH_HOME（原值：$dshHome）" -ForegroundColor Green
} else {
    $dshHome = Join-Path $env:USERPROFILE 'DeepSeek Harness'
    Write-Host '    未设置 DSH_HOME 环境变量，跳过'
}

# 3. 数据目录
if (Test-Path $dshHome) {
    if (Ask-YesNo "删除数据目录 $dshHome（包含所有会话记录）？" $false) {
        Remove-Item $dshHome -Recurse -Force
        Write-Host '    [OK] 已删除数据目录' -ForegroundColor Green
    } else {
        Write-Host '    已保留数据目录（如要手动删除，直接删掉该文件夹即可）'
    }
} else {
    Write-Host '    数据目录不存在，跳过'
}

# 4. npm 全局包
if (Ask-YesNo '卸载全局包 @deepseek-ai/dsh ？' $true) {
    & npm uninstall -g @deepseek-ai/dsh
    Write-Host '    [OK] 已卸载 dsh 全局包' -ForegroundColor Green
} else {
    Write-Host '    已保留 dsh 全局包'
}

Write-Host ''
Write-Host '卸载完成。' -ForegroundColor Green
