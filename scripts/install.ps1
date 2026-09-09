#requires -Version 5.1
<#
  DeepSeek Harness 一键安装脚本（Windows 10/11 64 位）

  功能：
    1. 检测 Node.js，缺失时用 winget（或官网安装包兜底）自动安装 LTS 版
    2. 用 npm 全局安装 @deepseek-ai/dsh（可选手动选择国内镜像源）
    3. 设置 DSH_HOME 用户环境变量，并创建数据目录与默认配置
    4. （可选）配置开机自启：登录后后台静默启动 Web 界面

  用法：双击「1-一键安装.bat」，或手动执行：
        powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1

  参数：
    -DryRun        只演示将要执行的步骤，不做任何实际修改
    -AssumeYes     所有提问自动回答“是”（适合无人值守）
    -HomeOverride  覆盖数据目录 DSH_HOME（默认 %USERPROFILE%\DeepSeek Harness）
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$AssumeYes,
    [string]$HomeOverride = ""
)

$ErrorActionPreference = 'Stop'

# ---------- 工具函数 ----------
function Write-Step  ([string]$msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok    ([string]$msg) { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Warn  ([string]$msg) { Write-Host "    [!!] $msg" -ForegroundColor Yellow }

function Refresh-PathEnv {
    # Node 装完后当前会话不会自动刷新 PATH，从注册表重新拼装
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

function Ask-YesNo([string]$question, [bool]$defaultYes) {
    if ($AssumeYes) { return $defaultYes }
    $suffix = if ($defaultYes) { '[Y/n]' } else { '[y/N]' }
    $answer = Read-Host "$question $suffix"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $defaultYes }
    return $answer.Trim().ToLower() -in @('y', 'yes', '是', '1')
}

# 查询 npm 上 @deepseek-ai/dsh 的已发布最新版本（尽力而为，失败不打断安装）
function Get-NpmLatestVersion {
    try {
        $v = & npm view '@deepseek-ai/dsh' version 2>$null
        return (($v | Select-Object -Last 1) -join '').Trim()
    } catch {
        return ''
    }
}

# ---------- 目标路径 ----------
$dshHome = if ($HomeOverride) { $HomeOverride } else { Join-Path $env:USERPROFILE 'DeepSeek Harness' }
$npmDir  = Join-Path $env:APPDATA 'npm'
$package = '@deepseek-ai/dsh'

Write-Host '==================================================' -ForegroundColor Magenta
Write-Host '   DeepSeek Harness 一键安装' -ForegroundColor Magenta
Write-Host '==================================================' -ForegroundColor Magenta
Write-Host ("   数据目录 (DSH_HOME) : {0}" -f $dshHome)
if ($DryRun) { Write-Host '   DRY RUN 模式：仅演示步骤，不做任何修改' -ForegroundColor Yellow }

# ---------- 1. Node.js ----------
Write-Step '检查 Node.js ...'
$node = Get-Command node -ErrorAction SilentlyContinue
$needNodeInstall = $false

if ($node) {
    $ver = (& node --version 2>$null) -join ''
    $major = 0
    if ($ver -match 'v(\d+)\.') { $major = [int]$Matches[1] }
    if ($major -ge 18) {
        Write-Ok "已安装 Node.js $ver（满足要求）"
    } else {
        Write-Warn "Node.js 版本过旧（$ver，需要 >= 18），将自动升级到 LTS 版"
        $needNodeInstall = $true
    }
} else {
    Write-Warn '未检测到 Node.js，将自动安装 LTS 版'
    $needNodeInstall = $true
}

if ($needNodeInstall) {
    if ($DryRun) {
        Write-Ok '[DRY] 将自动安装 Node.js LTS（winget 或官网安装包兜底）'
    } else {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host '    使用 winget 安装 Node.js LTS（如弹出 UAC 请点“是”）...'
            & winget install --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements --silent
            if ($LASTEXITCODE -ne 0) {
                throw 'winget 安装 Node.js 失败。请手动安装 https://nodejs.org 后重新运行本脚本。'
            }
        } else {
            Write-Host '    未找到 winget，改用官网安装包（自动下载 LTS x64 MSI）...'
            $idx = Invoke-RestMethod 'https://nodejs.org/dist/index.json'
            $latest = $idx | Where-Object { $_.version -like 'v22.*' } | Select-Object -First 1
            if (-not $latest) { $latest = $idx | Select-Object -First 1 }
            $url = "https://nodejs.org/dist/$($latest.version)/node-$($latest.version)-x64.msi"
            $msi = Join-Path $env:TEMP "node-$($latest.version)-x64.msi"
            Write-Host "    下载 $url ..."
            Invoke-WebRequest -Uri $url -OutFile $msi
            Write-Host '    静默安装（如弹出 UAC 请点“是”）...'
            $proc = Start-Process msiexec -ArgumentList "/i `"$msi`" /qn" -Verb RunAs -Wait -PassThru
            if ($proc.ExitCode -ne 0) {
                throw "Node.js 安装失败（退出码 $($proc.ExitCode)）"
            }
        }
        Refresh-PathEnv
        $node = Get-Command node -ErrorAction SilentlyContinue
        if (-not $node) {
            throw 'Node.js 安装完成后仍未找到 node，请关闭本窗口、重新打开一个终端后再试。'
        }
        Write-Ok "Node.js 就绪：$((& node --version 2>$null) -join '')"
    }
}

# ---------- 2. 安装 dsh（始终安装 @latest = 最新版） ----------
Write-Step "安装 $package（始终装最新版 @latest）..."
$registryArgs = @()
if ($DryRun) {
    Write-Ok '[DRY] 将执行：npm install -g @deepseek-ai/dsh@latest（默认国内镜像，可选手动换官方源）'
} else {
    # 显示当前已装版本 vs npm 最新版（尽力而为，失败不影响安装）
    $curVer = ((& dsh --version 2>$null) -join '').Trim()
    $latestVer = Get-NpmLatestVersion
    if ($curVer) { Write-Host ("    当前已装版本：{0}" -f $curVer) -ForegroundColor DarkGray }
    if ($latestVer) { Write-Host ("    npm 最新版本：{0}（将安装此版本）" -f $latestVer) -ForegroundColor DarkGray }

    $useMirror = Ask-YesNo '使用国内镜像源（npmmirror，通常更快）安装？' $true
    if ($useMirror) {
        $registryArgs = @('--registry', 'https://registry.npmmirror.com')
        Write-Ok '已选择国内镜像 https://registry.npmmirror.com'
    } else {
        Write-Ok '已选择官方源 https://registry.npmjs.org'
    }
    & npm install -g "$package@latest" @registryArgs
    if ($LASTEXITCODE -ne 0) {
        throw 'npm 安装 dsh 失败。请检查网络后重新运行本脚本。'
    }

    # 定位 dsh 命令（npm 全局目录可能在 PATH 里）
    $dshCmd = Join-Path $npmDir 'dsh.cmd'
    if (-not (Test-Path $dshCmd)) {
        $found = Get-Command dsh -ErrorAction SilentlyContinue
        $dshCmd = if ($found) { $found.Source } else { '' }
    }
    if (-not $dshCmd) { throw 'dsh 安装完成后未找到命令，请检查 npm 全局目录。' }
    Write-Ok "dsh 已安装：$dshCmd"
    Write-Ok "版本：$((& $dshCmd --version 2>$null) -join '')"
    if ($latestVer -and $curVer -and $curVer -ne $latestVer) {
        Write-Ok "已从 $curVer 升级到最新版 $latestVer"
    }
}

# ---------- 3. DSH_HOME 与默认配置 ----------
Write-Step '配置数据目录 (DSH_HOME) ...'
if (-not $DryRun) {
    [Environment]::SetEnvironmentVariable('DSH_HOME', $dshHome, 'User')
    Write-Ok "已设置用户环境变量 DSH_HOME=$dshHome（新开的终端会生效）"
}
if (-not (Test-Path $dshHome)) {
    if ($DryRun) {
        Write-Ok "[DRY] 将创建数据目录：$dshHome"
    } else {
        New-Item -ItemType Directory -Path $dshHome -Force | Out-Null
        Write-Ok "已创建数据目录：$dshHome"
    }
} else {
    Write-Ok "数据目录已存在：$dshHome"
}

$templateDir = Join-Path $PSScriptRoot 'template'
$settingsFile = Join-Path $dshHome 'settings.yaml'
$settingsTmpl = Join-Path $templateDir 'settings.yaml'

if (Test-Path $settingsFile) {
    Write-Ok 'settings.yaml 已存在，跳过（保留你已有的配置）'
} else {
    if ($DryRun) {
        Write-Ok '[DRY] 将写入默认 settings.yaml'
    } elseif (Test-Path $settingsTmpl) {
        Copy-Item -Path $settingsTmpl -Destination $settingsFile
        Write-Ok '已写入默认 settings.yaml'
    } else {
        Write-Warn '未找到 settings.yaml 模板，跳过（首次启动时应用会自动生成）'
    }
}

# API Key 不在此写入占位文件：应用首次启动时如无 Key 会弹出引导对话框，
# 之后用「2-配置APIKey.bat」或 Web 界面的 Settings → Models 填写即可。
if (-not (Test-Path (Join-Path $dshHome '.credentials.yaml'))) {
    Write-Ok '尚未配置 API Key：安装完成后请运行「2-配置APIKey.bat」粘贴你的 Key'
}

# ---------- 4. 开机自启（可选） ----------
Write-Step '开机自启（可选）...'
$startupDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
$vbsPath = Join-Path $startupDir 'dsh-web-autostart.vbs'

if (Test-Path $vbsPath) {
    Write-Ok '开机自启已存在（删除 dsh-web-autostart.vbs 即可取消）'
} elseif ($DryRun) {
    Write-Ok '[DRY] 将创建开机自启脚本（后台静默启动 Web 界面）'
} elseif (Ask-YesNo '配置开机自动启动 Web 界面（登录后后台静默运行）？' $true) {
    $vbs = @'
' DeepSeek Harness web UI - silent autostart (no console window)
' Runs "dsh web" hidden at user logon. Delete this file to disable.
Set shell = CreateObject("WScript.Shell")
home = shell.ExpandEnvironmentStrings("%USERPROFILE%")
dsh = shell.ExpandEnvironmentStrings("%APPDATA%") & "\npm\dsh.cmd"
shell.Environment("PROCESS")("DSH_HOME") = home & "\DeepSeek Harness"
shell.CurrentDirectory = home
shell.Run "cmd.exe /c """ & dsh & """ web", 0, False
'@
    Set-Content -Path $vbsPath -Value $vbs -Encoding ASCII
    Write-Ok "已创建开机自启：$vbsPath"
} else {
    Write-Ok '已跳过开机自启'
}

# ---------- 5. 完成 ----------
Write-Step '安装完成！'
Write-Host ''
Write-Host '  接下来（三步）：' -ForegroundColor Green
Write-Host '    1. 双击「2-配置APIKey.bat」，粘贴你的 DeepSeek API Key'
Write-Host '       （没有 Key 可到 https://platform.deepseek.com 的 API Keys 页面创建）'
Write-Host '    2. 双击「3-启动Web界面.bat」，浏览器自动打开 http://127.0.0.1:3080'
Write-Host '    3. 首次打开会引导初始化，之后即可对话'
Write-Host ''
Write-Host ("  数据目录：{0}" -f $dshHome) -ForegroundColor Cyan
Write-Host '  会话记录、设置、API Key 都在这个文件夹里，备份直接复制它即可。'
Write-Host '  更详细的说明见安装包里的《使用说明.md》。'
Write-Host ''
if ($DryRun) { Write-Host '  （以上为 DRY RUN 演示，未做任何实际修改）' -ForegroundColor Yellow }
