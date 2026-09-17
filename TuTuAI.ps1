# 手机智控程序（随仓库 git 到 GitHub）
# 技能下载本文件并执行。同目录的 TuTuAI-Setup.exe 是安装包（npm run pack:win 生成后再 git add）。

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo = if ($env:TUTU_GITHUB_REPO) { $env:TUTU_GITHUB_REPO } else { "Knight123457/PhoneControl" }
$Branch = if ($env:TUTU_GITHUB_BRANCH) { $env:TUTU_GITHUB_BRANCH } else { "main" }
$SetupName = "TuTuAI-Setup.exe"
$Bridge = "http://127.0.0.1:3000"
$Token = "tutu-local"
# electron-builder per-user 目录用 package.json 的 name（tutu-ai），不是 productName
$InstallRoot = Join-Path $env:LOCALAPPDATA "Programs\tutu-ai"
$Here = $PSScriptRoot
if (-not $Here) { $Here = $env:TEMP }

function Write-Info($msg) { Write-Host "[TuTuAI] $msg" }

function Test-Bridge {
  try {
    Invoke-RestMethod -Uri "$Bridge/api/bridge/health" -TimeoutSec 3 | Out-Null
    return $true
  } catch {
    return $false
  }
}

function Get-SetupFile {
  $local = Join-Path $Here $SetupName
  if (Test-Path $local) { return $local }

  $urls = @(
    "https://github.com/$Repo/releases/latest/download/$SetupName",
    "https://raw.githubusercontent.com/$Repo/$Branch/publish/github/$SetupName"
  )
  $tmp = Join-Path $env:TEMP $SetupName
  foreach ($url in $urls) {
    Write-Info "downloading $url"
    try {
      Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
      if ((Test-Path $tmp) -and (Get-Item $tmp).Length -gt 10000) { return $tmp }
    } catch { }
  }
  throw "Missing $SetupName. Upload it as a GitHub Release asset on $Repo (npm run pack:win)."
}

function Install-Setup {
  $exe = Join-Path $InstallRoot "TuTuAI.exe"
  if (Test-Path $exe) {
    Write-Info "already installed: $exe"
    return $exe
  }
  $setup = Get-SetupFile
  Write-Info "running installer..."
  Start-Process -FilePath $setup -ArgumentList "/S" -Wait
  if (-not (Test-Path $exe)) { throw "install finished but missing $exe" }
  return $exe
}

function Start-Ui($exe) {
  if (-not (Test-Bridge)) { Start-Process $exe }
  for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Seconds 2
    if (Test-Bridge) { return }
  }
  throw "app started but $Bridge is not ready"
}

function Merge-Mcp($path, $nodeExe, $serverJs) {
  $dir = Split-Path $path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $cfg = @{ mcpServers = @{} }
  if (Test-Path $path) {
    try { $cfg = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    if (-not $cfg.mcpServers) {
      $cfg | Add-Member -NotePropertyName mcpServers -NotePropertyValue (@{}) -Force
    }
  }
  $entry = [pscustomobject]@{
    type    = "stdio"
    command = $nodeExe
    args    = @($serverJs)
    env     = [pscustomobject]@{
      TUTU_BRIDGE_URL   = $Bridge
      TUTU_BRIDGE_TOKEN = $Token
    }
  }
  $cfg.mcpServers | Add-Member -NotePropertyName "phone-control" -NotePropertyValue $entry -Force
  Set-Content -Path $path -Value ($cfg | ConvertTo-Json -Depth 8) -Encoding UTF8
  Write-Info "wrote MCP $path"
}

$exe = Install-Setup
Start-Ui $exe
$res = Join-Path $InstallRoot "resources"
$nodeExe = (Join-Path $res "node.exe").Replace("\", "/")
$serverJs = (Join-Path $res "mcp\server.mjs").Replace("\", "/")
if (-not (Test-Path ($nodeExe.Replace("/", "\")))) { $nodeExe = "node" }
Merge-Mcp (Join-Path $env:USERPROFILE ".workbuddy\mcp.json") $nodeExe $serverJs
Merge-Mcp (Join-Path $env:USERPROFILE ".cursor\mcp.json") $nodeExe $serverJs
Write-Info "done. Click Connect Phone, then open a NEW chat."
