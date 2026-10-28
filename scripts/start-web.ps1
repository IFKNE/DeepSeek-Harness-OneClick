#requires -Version 5.1
<#
  DeepSeek Harness：启动 Web 界面并自动打开浏览器

  用法：双击「3-启动Web界面.bat」。
  参数：
    -Port         监听端口（默认 3080）
    -HomeOverride 覆盖数据目录（默认读 DSH_HOME）

  关于浏览器鉴权（为什么有时会提示 authentication required）：
    dsh web 启动时会打印一行带令牌的地址：
        dsh web: http://127.0.0.1:3080/?token=<本次进程的随机令牌>
    只有用这个地址打开一次，浏览器才会拿到一个 30 天有效的 Cookie；之后
    裸地址 http://127.0.0.1:3080 才能直接访问。令牌每次启动都变、且只存在
    进程内存里，所以：
      * 本脚本会把 dsh web 的输出（含那一行带令牌地址）记录到
        %DSH_HOME%\web-url.txt；
      * 端口已在监听时（例如后台/开机自启已经在跑），从该文件取回带令牌
        地址、并真的发一个请求验证它还有效，再打开浏览器——不再像以前
        那样只打开不带令牌的裸地址。
    另外：端口探测用 TCP 连接 + 文件校验，不依赖 Get-NetTCPConnection
    （后者在部分机器上会“拒绝访问”，导致误判端口空闲）。
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

$url     = "http://127.0.0.1:$Port"
$urlFile = Join-Path $dshHome 'web-url.txt'

# ---------- 工具函数 ----------
function Save-LogLine([string]$Path, [string]$Line) {
    # 按 UTF-8（无 BOM）追加一行；写文件失败不该打断启动
    try {
        [System.IO.File]::AppendAllText($Path, $Line + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
    } catch { }
}

function Read-TokenUrl([string]$Path, [int]$Port) {
    # 从 web-url.txt 里取出“最后一条”带令牌地址。文件可能是 UTF-8/ANSI 字节
    # （cmd 重定向 / 本脚本写出），也可能是 UTF-16（PowerShell 默认写出），
    # Get-Content 两种都能读。
    if (-not (Test-Path $Path)) { return '' }
    try { $text = Get-Content -Path $Path -Raw -ErrorAction Stop } catch { return '' }
    if (-not $text) { return '' }
    $pattern = 'http://127\.0\.0\.1:' + $Port + '/\?token=[A-Za-z0-9_\-]+'
    $found = [regex]::Matches($text, $pattern)
    if ($found.Count -eq 0) { return '' }
    return $found[$found.Count - 1].Value
}

function Test-PortServing([int]$Port) {
    # 轻量 TCP 连接探测：不依赖 WMI/管理员权限
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect('127.0.0.1', $Port)
        $client.Close()
        return $true
    } catch {
        return $false
    }
}

function Test-TokenUrl([string]$Candidate) {
    # 直接问服务器这个带令牌地址还有效吗：有效会 303 跳到 /，失效则是 401。
    # 探测失败（网络/权限等）时按“有效”处理，避免误报把好地址丢掉。
    try {
        $req = [System.Net.HttpWebRequest]::Create($Candidate)
        $req.AllowAutoRedirect = $false
        $req.Timeout = 8000
        $req.ReadWriteTimeout = 8000
        $resp = $req.GetResponse()
        $code = [int]$resp.StatusCode
        $resp.Close()
        return ($code -ge 200 -and $code -lt 400)
    } catch {
        # PowerShell 会把 .NET 异常包一层，需要往下剥到 WebException 才拿得到响应
        $err = $_.Exception
        while ($err -and $err.InnerException -and -not ($err -is [System.Net.WebException])) { $err = $err.InnerException }
        $resp = $null
        if ($err -is [System.Net.WebException]) { $resp = $err.Response }
        if ($resp) {
            $code = [int]$resp.StatusCode
            $resp.Close()
            return ($code -ne 401)
        }
        return $true
    }
}

function Get-LiveTokenUrl([string]$Path, [int]$Port) {
    # 只有“服务器认可”的令牌才会被采用：这样上一次进程留下的失效令牌不会被误用
    $candidate = Read-TokenUrl -Path $Path -Port $Port
    if (-not $candidate) { return '' }
    if (Test-TokenUrl -Candidate $candidate) { return $candidate }
    return ''
}

# ---------- 定位 dsh ----------
$dsh = Get-Command dsh -ErrorAction SilentlyContinue
if (-not $dsh) {
    $cand = Join-Path $env:APPDATA 'npm\dsh.cmd'
    if (Test-Path $cand) { $dsh = $cand } else {
        Write-Host '未找到 dsh 命令。请先运行「1-一键安装.bat」安装。' -ForegroundColor Yellow
        exit 1
    }
}

# ---------- 端口已被占用？ ----------
if (Test-PortServing -Port $Port) {
    $stored = Get-LiveTokenUrl -Path $urlFile -Port $Port
    if ($stored) {
        Write-Host "端口 $Port 已在监听，使用仍在生效的带令牌地址打开浏览器：" -ForegroundColor Cyan
        Write-Host "  $stored"
        Start-Process $stored
        exit 0
    }
    Write-Host "端口 $Port 已在监听（dsh 可能已在运行），但没有可用的带令牌地址。" -ForegroundColor Yellow
    Write-Host "若浏览器提示 authentication required：先结束正在运行的 node.exe，再用本脚本启动一次。" -ForegroundColor Yellow
    Start-Process $url
    exit 0
}

Write-Host "启动 dsh web（端口 $Port），就绪后自动打开浏览器。" -ForegroundColor Cyan
Write-Host '按 Ctrl+C 可停止。' -ForegroundColor DarkGray

# 清掉上一次进程留下的令牌地址，避免误用已失效的令牌
Remove-Item $urlFile -Force -ErrorAction SilentlyContinue

# dsh 自己的浏览器弹窗用 --no-open 关掉：改由这里在“读到带令牌地址”的瞬间
# 打开浏览器，保证打开的一定是能通过鉴权的地址。
$opened = $false
& $dsh web --port $Port --no-open | ForEach-Object {
    $line = [string]$_
    Save-LogLine -Path $urlFile -Line $line
    if (-not $opened -and $line -match 'dsh web:\s*(http://127\.0\.0\.1:\d+/\?token=[A-Za-z0-9_\-]+)') {
        $opened = $true
        $target = $Matches[1]
        Write-Host "已就绪，正在打开浏览器：$target" -ForegroundColor Green
        Write-Host "（带令牌地址已记到 $urlFile，重启后自动更新）" -ForegroundColor DarkGray
        try { Start-Process $target } catch { Write-Host '打开浏览器失败，请手动复制下面那行地址。' -ForegroundColor Yellow }
    }
    Write-Host $line
}

if (-not $opened) {
    Write-Host "没有从输出里识别到带令牌地址；请手动复制窗口里 'dsh web: http://...' 那一行到浏览器。" -ForegroundColor Yellow
    Write-Host "（dsh web 已退出，退出码 $LASTEXITCODE）" -ForegroundColor DarkGray
} else {
    Write-Host "dsh web 已退出（退出码 $LASTEXITCODE）。" -ForegroundColor DarkGray
}
