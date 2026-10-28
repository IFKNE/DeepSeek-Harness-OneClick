Set-StrictMode -Version Latest

function Get-DshInstallPaths {
    param(
        [string]$LocalAppData = $env:LOCALAPPDATA,
        [string]$UserProfile = $env:USERPROFILE
    )
    [pscustomobject]@{
        LauncherRoot = Join-Path $LocalAppData 'Programs\DeepSeek Harness'
        DataRoot = Join-Path $UserProfile 'DeepSeek Harness'
        Manifest = Join-Path $LocalAppData 'Programs\DeepSeek Harness\installer-manifest.json'
        Launcher = Join-Path $LocalAppData 'Programs\DeepSeek Harness\DeepSeek Harness.exe'
        Icon = Join-Path $LocalAppData 'Programs\DeepSeek Harness\DeepSeekHarness.ico'
        LogRoot = Join-Path $UserProfile 'DeepSeek Harness\installer-logs'
    }
}

function Read-InstallerManifest { param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $text = Get-Content -LiteralPath $Path -Raw
    try { return ($text | ConvertFrom-Json) } catch {
        # 兼容早期版本把 C:\Users\... 写成单反斜杠的清单。
        $repairedText = $text -creplace '(?<!\\)\\(?!["\\/bfnrtu])', '\\'
        $repaired = $repairedText | ConvertFrom-Json
        [IO.File]::WriteAllText($Path, ($repaired | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
        return $repaired
    }
}

function Write-InstallerManifest { param([object]$Manifest, [string]$Path)
    $dir = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    [IO.File]::WriteAllText($Path, ($Manifest | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
}

function Get-FileSha256 { param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "文件不存在：$Path" }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Copy-FileVerified { param([string]$Source, [string]$Destination)
    if (-not (Test-Path -LiteralPath $Source)) { throw "安装包资源不存在：$Source" }
    $dir = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    if ((Get-FileSha256 $Source) -ne (Get-FileSha256 $Destination)) { throw "文件校验失败：$Destination" }
}

function ConvertTo-DshRedactedText { param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return '' }
    $result = $Text -replace '(?i)(token=)[A-Za-z0-9_\-]+', '$1<redacted>'
    $result = $result -replace '(?i)(Bearer\s+)[^\s,;]+', '$1<redacted>'
    $result = $result -replace '(?i)(sk-[A-Za-z0-9_\-]+)', '<redacted>'
    $result -replace '(?i)(api[_-]?key\s*[:=]\s*)[^\s,;]+', '$1<redacted>'
}

function Write-DshLog { param([string]$Message, [string]$Path)
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    $line = "[$([DateTime]::Now.ToString('s'))] $(ConvertTo-DshRedactedText $Message)"
    [IO.File]::AppendAllText($Path, $line + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}

function Get-DshListener { param([int]$Port = 3080)
    try {
        $client = [Net.Sockets.TcpClient]::new()
        $client.Connect('127.0.0.1', $Port)
        $client.Close()
        return $true
    } catch { return $false }
}

function Test-DshWebHealth { param([int]$Port = 3080)
    if (-not (Get-DshListener $Port)) { return $false }
    try {
        $request = [Net.HttpWebRequest]::Create("http://127.0.0.1:$Port/")
        $request.Timeout = 5000
        $response = $request.GetResponse()
        $code = [int]$response.StatusCode
        $response.Close()
        return ($code -ge 200 -and $code -lt 500)
    } catch {
        return $true
    }
}

Export-ModuleMember -Function Get-DshInstallPaths,Read-InstallerManifest,Write-InstallerManifest,Get-FileSha256,Copy-FileVerified,ConvertTo-DshRedactedText,Write-DshLog,Get-DshListener,Test-DshWebHealth
