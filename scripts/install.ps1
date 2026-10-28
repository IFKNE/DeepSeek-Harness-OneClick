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
    -NoWinget      跳过 winget，直接用国内镜像/官网的 MSI 安装包装 Node.js
                   （winget 报 0x8A15005E 证书错误、或公司网络拦截 winget 源时用得上）
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$AssumeYes,
    [switch]$NoWinget,
    [switch]$NoNodeInstall,
    [switch]$NoDshInstall,
    [string]$HomeOverride = "",
    [switch]$NoScheduledTask,
    [string]$InstallRootOverride = "",
    [switch]$WhatIfLauncher
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

function Enable-Tls12 {
    # Windows PowerShell 5.1 在部分机器上默认不启用 TLS 1.2，会让下载直接失败
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
}

function Get-RemoteFile([string]$url, [string]$outFile) {
    # 下载文件：先试 Invoke-WebRequest，失败再退到系统自带 curl.exe（对代理/证书差异更宽容）
    try {
        Invoke-WebRequest -Uri $url -OutFile $outFile -UseBasicParsing -TimeoutSec 120
        return $true
    } catch {
        Write-Warn ("Invoke-WebRequest 下载失败：{0}" -f $_.Exception.Message)
    }
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        Write-Host ("    改用 curl 重试 ...") -ForegroundColor DarkGray
        & $curl.Source -L --fail --retry 2 --connect-timeout 30 -o $outFile $url 2>$null
        if ($LASTEXITCODE -eq 0 -and (Test-Path $outFile) -and (Get-Item $outFile).Length -gt 0) { return $true }
    }
    return $false
}

function Get-NodeLtsVersion {
    # 取最新 LTS 版本号：国内镜像优先，官网兜底
    $indexUrls = @(
        'https://registry.npmmirror.com/-/binary/node/index.json',
        'https://cdn.npmmirror.com/binaries/node/index.json',
        'https://nodejs.org/dist/index.json'
    )
    foreach ($u in $indexUrls) {
        try {
            $idx = Invoke-RestMethod -Uri $u -UseBasicParsing -TimeoutSec 60
            $lts = $idx | Where-Object { $_.lts } | Select-Object -First 1
            if (-not $lts) { $lts = $idx | Where-Object { $_.version -like 'v22.*' } | Select-Object -First 1 }
            if (-not $lts) { $lts = $idx | Select-Object -First 1 }
            if ($lts -and $lts.version) { return [string]$lts.version }
        } catch {
            Write-Warn ("获取版本列表失败（{0}）：{1}" -f $u, $_.Exception.Message)
        }
    }
    return ''
}

function Install-NodeFromMsi {
    # winget 不可用或失败时的兜底：下载 LTS 的 x64 MSI 静默安装
    Enable-Tls12
    $ver = Get-NodeLtsVersion
    if (-not $ver) {
        throw '无法获取 Node.js 版本信息（网络不通，或被代理/安全软件拦截）。请手动从 https://nodejs.org/zh-cn 下载 LTS 安装包，装好后重新运行本脚本。'
    }

    $arch = 'x64'
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $arch = 'arm64' }
    $file = "node-$ver-$arch.msi"
    $mirrors = @(
        "https://registry.npmmirror.com/-/binary/node/$ver/$file",
        "https://cdn.npmmirror.com/binaries/node/$ver/$file",
        "https://npmmirror.com/mirrors/node/$ver/$file",
        "https://nodejs.org/dist/$ver/$file"
    )

    $msi = Join-Path $env:TEMP $file
    if (Test-Path $msi) { Remove-Item $msi -Force -ErrorAction SilentlyContinue }

    $ok = $false
    foreach ($m in $mirrors) {
        Write-Host ("    下载 {0} ..." -f $m)
        if (Get-RemoteFile -url $m -outFile $msi) {
            $size = (Get-Item $msi).Length
            if ($size -gt 10MB) {
                Write-Ok ("已下载 {0}（{1:N1} MB）" -f $file, ($size / 1MB))
                $ok = $true
                break
            }
            Write-Warn ("下载文件过小（{0} 字节），换下一个源重试" -f $size)
        } else {
            Write-Warn '该源不可用，换下一个源重试'
        }
    }
    if (-not $ok) {
        throw "Node.js 安装包下载失败（网络不通或被代理/安全软件拦截）。请手动下载安装：https://nodejs.org/zh-cn 或国内镜像 https://npmmirror.com/mirrors/node/ 里的 $file，装好后重新运行本脚本。"
    }

    Write-Host '    静默安装（如弹出 UAC 请点“是”）...'
    $proc = Start-Process msiexec -ArgumentList "/i `"$msi`" /qn /norestart" -Verb RunAs -Wait -PassThru
    # 3010 = 安装成功但需要重启，视为成功
    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
        throw "Node.js 安装失败（msiexec 退出码 $($proc.ExitCode)）。请手动从 https://nodejs.org/zh-cn 下载安装包安装，装好后重新运行本脚本。"
    }
}

function Resolve-DshCmd {
    # 定位 dsh 命令：优先 npm 全局目录，其次 PATH；未安装时返回空字符串。
    # 注意：$ErrorActionPreference='Stop' 下，直接 & dsh 会抛出终止性错误，必须先探测。
    $candidate = Join-Path $npmDir 'dsh.cmd'
    if (Test-Path $candidate) { return $candidate }
    $found = Get-Command dsh -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    return ''
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
        $v = & npm view '@deepseek-ai/dsh' version --fetch-timeout=10000 --fetch-retries=0 2>$null
        return (($v | Select-Object -Last 1) -join '').Trim()
    } catch {
        return ''
    }
}

function Install-NativeLauncher {
    param([string]$DataRoot, [switch]$SkipTask)
    $common = Join-Path $PSScriptRoot 'lib\InstallerCommon.psm1'
    Import-Module $common -Force
    $paths = Get-DshInstallPaths
    if ($InstallRootOverride) {
        $paths = [pscustomobject]@{
            LauncherRoot = $InstallRootOverride
            DataRoot = $DataRoot
            Manifest = Join-Path $InstallRootOverride 'installer-manifest.json'
            Launcher = Join-Path $InstallRootOverride 'DeepSeek Harness.exe'
            Icon = Join-Path $InstallRootOverride 'DeepSeekHarness.ico'
            LogRoot = Join-Path $DataRoot 'installer-logs'
        }
    }
    $sourceRoot = Split-Path $PSScriptRoot -Parent
    $manifestSource = Join-Path $sourceRoot 'installer-manifest.json'
    $launcherSource = Join-Path $sourceRoot 'launcher\bin\DeepSeek Harness.exe'
    $iconSource = Join-Path $sourceRoot 'launcher\assets\DeepSeekHarness.ico'
    if ($WhatIfLauncher) {
        Write-Ok "[DRY] 原生启动器目标：$($paths.Launcher)"
        Write-Ok "[DRY] 图标目标：$($paths.Icon)"
        return
    }
    if (-not (Test-Path -LiteralPath $launcherSource)) { throw "安装包缺少原生启动器：$launcherSource" }
    if (-not (Test-Path -LiteralPath $iconSource)) { throw "安装包缺少官方图标：$iconSource" }
    New-Item -ItemType Directory -Path $paths.LauncherRoot -Force | Out-Null
    Copy-FileVerified $launcherSource $paths.Launcher
    Copy-FileVerified $iconSource $paths.Icon
    $installedScriptRoot = Join-Path $paths.LauncherRoot 'installer\scripts'
    New-Item -ItemType Directory -Path $installedScriptRoot -Force | Out-Null
    Copy-FileVerified (Join-Path $PSScriptRoot 'update.ps1') (Join-Path $installedScriptRoot 'update.ps1')
    New-Item -ItemType Directory -Path (Join-Path $installedScriptRoot 'lib') -Force | Out-Null
    Copy-FileVerified (Join-Path $PSScriptRoot 'lib\InstallerCommon.psm1') (Join-Path $installedScriptRoot 'lib\InstallerCommon.psm1')
    $manifest = if (Test-Path -LiteralPath $manifestSource) { Read-InstallerManifest $manifestSource } else { [pscustomobject]@{ installerVersion = '0.3.0'; launcherVersion = '0.3.0' } }
    $manifest | Add-Member NoteProperty dataRoot $paths.DataRoot -Force
    $manifest | Add-Member NoteProperty installedAt ([DateTime]::Now.ToString('o')) -Force
    Write-InstallerManifest $manifest $paths.Manifest

    $desktop = [Environment]::GetFolderPath('Desktop')
    $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\DeepSeek Harness'
    New-Item -ItemType Directory -Path $startMenu -Force | Out-Null
    $shell = New-Object -ComObject WScript.Shell
    foreach ($shortcutPath in @((Join-Path $desktop 'DeepSeek Harness.lnk'), (Join-Path $startMenu 'DeepSeek Harness.lnk'))) {
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $paths.Launcher
        $shortcut.WorkingDirectory = $paths.LauncherRoot
        $shortcut.IconLocation = "$($paths.Icon),0"
        $shortcut.Description = 'DeepSeek Harness'
        $shortcut.Save()
    }
    if (-not $SkipTask) {
        $register = Join-Path $PSScriptRoot 'register-update-task.ps1'
        if (Test-Path -LiteralPath $register) { & powershell -NoProfile -ExecutionPolicy Bypass -File $register -DataRoot $DataRoot -ScriptRoot $installedScriptRoot }
    }
    Write-Ok "已安装原生启动器：$($paths.Launcher)"
    Write-Ok '已创建桌面和开始菜单快捷方式'
}

# ---------- 目标路径 ----------
# 已有用户优先沿用原 DSH_HOME，避免安装后看不到旧会话；新用户才使用默认目录。
$existingDshHome = [Environment]::GetEnvironmentVariable('DSH_HOME', 'User')
$dshHome = if ($HomeOverride) { $HomeOverride } elseif ($existingDshHome) { $existingDshHome } else { Join-Path $env:USERPROFILE 'DeepSeek Harness' }
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

if ($needNodeInstall -and $NoNodeInstall) {
    Write-Warn '已指定 -NoNodeInstall，跳过 Node.js 安装（仅适合测试或已有外部 Node 的环境）'
} elseif ($needNodeInstall) {
    if ($DryRun) {
        Write-Ok '[DRY] 将自动安装 Node.js LTS（优先 winget，失败自动改用国内镜像/官网 MSI）'
    } else {
        $nodeInstalled = $false

        if (-not $NoWinget -and (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Host '    使用 winget 安装 Node.js LTS（如弹出 UAC 请点“是”）...'
            # --source winget：避免 winget 在多个源之间“找到多个包但不指定源”的歧义报错
            & winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-package-agreements --accept-source-agreements --silent
            if ($LASTEXITCODE -eq 0) {
                $nodeInstalled = $true
            } else {
                Write-Warn ("winget 安装失败（退出码 {0}；0x8A15005E 表示 winget 源证书校验失败）" -f $LASTEXITCODE)
                Write-Warn '自动改用国内镜像/官网的 MSI 安装包兜底（无需 winget）...'
            }
        } elseif ($NoWinget) {
            Write-Host '    已指定 -NoWinget，直接用国内镜像/官网安装包（自动下载 LTS MSI）...'
        } else {
            Write-Host '    未找到 winget，改用国内镜像/官网安装包（自动下载 LTS MSI）...'
        }

        if (-not $nodeInstalled) { Install-NodeFromMsi }

        Refresh-PathEnv
        $node = Get-Command node -ErrorAction SilentlyContinue
        if (-not $node) {
            # PATH 偶尔刷新不及时：直接找默认安装位置再补一次
            $defaultNode = Join-Path ${env:ProgramFiles} 'nodejs\node.exe'
            if (Test-Path $defaultNode) {
                $env:Path = "$(Split-Path $defaultNode);$env:Path"
                $node = Get-Command node -ErrorAction SilentlyContinue
            }
        }
        if (-not $node) {
            throw 'Node.js 安装完成后仍未找到 node，请关闭本窗口、重新打开一个终端后再试。'
        }
        Write-Ok "Node.js 就绪：$((& node --version 2>$null) -join '')"
    }
}

# ---------- 2. 安装 dsh（始终安装 @latest = 最新版） ----------
Write-Step "安装 $package（始终装最新版 @latest）..."
$registryArgs = @()
if ($DryRun -or $NoDshInstall) {
    Write-Ok '[DRY] 将执行：npm install -g @deepseek-ai/dsh@latest（默认国内镜像，可选手动换官方源）'
} else {
    # 显示当前已装版本 vs npm 最新版（尽力而为，失败不影响安装）
    $curVer = ''
    $existingDsh = Resolve-DshCmd
    if ($existingDsh) {
        try { $curVer = ((& $existingDsh --version 2>$null) -join '').Trim() } catch { $curVer = '' }
    }
    $latestVer = Get-NpmLatestVersion
    if ($curVer) { Write-Host ("    当前已装版本：{0}" -f $curVer) -ForegroundColor DarkGray }
    if ($latestVer) { Write-Host ("    npm 最新版本：{0}（将安装此版本）" -f $latestVer) -ForegroundColor DarkGray }

    $sameVersion = $curVer -and $latestVer -and ($curVer.TrimStart('v') -eq $latestVer.TrimStart('v'))
    if ($sameVersion) {
        Write-Ok "dsh 已是最新版 $curVer，跳过 npm 重装"
    } else {
        $useMirror = Ask-YesNo '使用国内镜像源（npmmirror，通常更快）安装？' $true
        if ($useMirror) {
            $registryArgs = @('--registry', 'https://registry.npmmirror.com')
            Write-Ok '已选择国内镜像 https://registry.npmmirror.com'
        } else {
            Write-Ok '已选择官方源 https://registry.npmjs.org'
        }
        & npm install -g "$package@latest" @registryArgs --fetch-timeout=30000 --fetch-retries=1
        if ($LASTEXITCODE -ne 0) {
            throw 'npm 安装 dsh 失败。请检查网络后重新运行本脚本。'
        }

        # 定位 dsh 命令（npm 全局目录可能在 PATH 里）
        $dshCmd = Resolve-DshCmd
        if (-not $dshCmd) { throw 'dsh 安装完成后未找到命令，请检查 npm 全局目录。' }
        Write-Ok "dsh 已安装：$dshCmd"
        Write-Ok "版本：$((& $dshCmd --version 2>$null) -join '')"
        if ($latestVer -and $curVer -and $curVer -ne $latestVer) {
            Write-Ok "已从 $curVer 升级到最新版 $latestVer"
        }
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

# ---------- 4. 原生启动器与每日检查 ----------
Write-Step '安装原生启动器与快捷方式 ...'
if ($DryRun) {
    Install-NativeLauncher -DataRoot $dshHome -SkipTask
} else {
    Install-NativeLauncher -DataRoot $dshHome -SkipTask:$NoScheduledTask
}

# 不再默认创建登录自启；保留旧 VBS 仅用于兼容旧用户已有的启动项。
Write-Step '登录自启 ...'
$startupDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
$vbsPath = Join-Path $startupDir 'dsh-web-autostart.vbs'

$vbs = @'
' DeepSeek Harness web UI - silent autostart (no console window)
' Runs "dsh web" hidden at user logon. Delete this file to disable.
' --no-open is required: dsh web opens the default browser by itself, which
' would pop a browser window on every logon.
' The output is redirected into web-url.txt: dsh web prints the authenticated
' URL (http://127.0.0.1:3080/?token=...) only once, and a hidden window would
' otherwise lose it -- opening the bare http://127.0.0.1:3080 in a browser
' without a cookie answers "dsh web authentication required".
Set shell = CreateObject("WScript.Shell")
home = shell.ExpandEnvironmentStrings("%USERPROFILE%")
dsh = shell.ExpandEnvironmentStrings("%APPDATA%") & "\npm\dsh.cmd"
dshHome = shell.ExpandEnvironmentStrings("%DSH_HOME%")
If dshHome = "%DSH_HOME%" Then dshHome = home & "\DeepSeek Harness"
shell.Environment("PROCESS")("DSH_HOME") = dshHome
shell.CurrentDirectory = dshHome
shell.Run "cmd.exe /S /c """"" & dsh & """ web --no-open > """ & dshHome & "\web-url.txt"" 2>&1""", 0, False
'@

if (Test-Path $vbsPath) { Write-Warn "检测到旧登录自启，已保留不改：$vbsPath" }
else { Write-Ok '默认不启用登录自启；使用桌面图标按需启动' }

# ---------- 5. 完成 ----------
Write-Step '安装完成！'
Write-Host ''
Write-Host '  接下来（三步）：' -ForegroundColor Green
Write-Host '    1. 双击「2-配置APIKey.bat」，粘贴你的 DeepSeek API Key'
Write-Host '       （没有 Key 可到 https://platform.deepseek.com 的 API Keys 页面创建）'
Write-Host '    2. 双击桌面或开始菜单中的「DeepSeek Harness」图标'
Write-Host '    3. 首次打开会引导初始化，之后即可对话'
Write-Host ''
Write-Host ("  数据目录：{0}" -f $dshHome) -ForegroundColor Cyan
Write-Host '  会话记录、设置、API Key 都在这个文件夹里，备份直接复制它即可。'
Write-Host '  更详细的说明见安装包里的《使用说明.md》。'
Write-Host '  每日更新只检查并提示，不会未经确认自动安装。'
Write-Host ''
if ($DryRun) { Write-Host '  （以上为 DRY RUN 演示，未做任何实际修改）' -ForegroundColor Yellow }
