#requires -Version 5.1
<#
  DeepSeek Harness：启动 Web 界面并自动打开浏览器

  用法：双击「3-启动Web界面.bat」。
  参数：
    -Port         监听端口（默认 3080）
    -HomeOverride 覆盖数据目录（默认读 DSH_HOME）
#>
[CmdletBinding()]
param(
    [int]$Port = 3080,
    [string]$HomeOverride = ""
)

$ErrorActionPreference = 'Stop'

# ---------- 确保 DSH_HOME 生效 ----------
$dshHome = $HomeOverride
if (-not $dshHome) { $dshHome = $env:DSH_HOME }
if (-not $dshHome) { $dshHome = [Environment]::GetEnvironmentVariable('DSH_HOME', 'User') }
if (-not $dshHome) { $dshHome = Join-Path $env:USERPROFILE 'DeepSeek Harness' }
$env:DSH_HOME = $dshHome

# ---------- 定位 dsh ----------
$dsh = Get-Command dsh -ErrorAction SilentlyContinue
if (-not $dsh) {
    $cand = Join-Path $env:APPDATA 'npm\dsh.cmd'
    if (Test-Path $cand) { $dsh = $cand } else {
        Write-Host '未找到 dsh 命令。请先运行「1-一键安装.bat」安装。' -ForegroundColor Yellow
        exit 1
    }
}

$url = "http://127.0.0.1:$Port"

# ---------- 端口已被占用？ ----------
$listening = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($listening) {
    Write-Host "端口 $Port 已在监听（可能 dsh 已在运行），直接打开浏览器 ..."
    Start-Process $url
    exit 0
}

Write-Host "启动 dsh web（端口 $Port），稍后自动打开浏览器：$url" -ForegroundColor Cyan
Write-Host '按 Ctrl+C 可停止。' -ForegroundColor DarkGray

# 后台延迟打开浏览器（dsh 启动需要几秒）
Start-Job -ScriptBlock {
    param($u, $p)
    # 轮询端口就绪后再开浏览器（首次启动初始化可能较慢）
    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline) {
        $c = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
        if ($c) { try { Start-Process $u } catch { }; return }
        Start-Sleep -Seconds 2
    }
} -ArgumentList $url, $Port | Out-Null

# --no-open：dsh web 自身默认也会开浏览器，会和上面的 Start-Job 撞成两个标签页。
# 这里交给 Start-Job 开（它会等端口就绪），所以把 dsh 自己的那份关掉。
& $dsh web --port $Port --no-open
