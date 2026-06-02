#Requires -Version 5.1
<#
  Download and extract portable Ollama into the project (no GUI installer).
  Models are stored under data/ollama/models (see start-ollama.ps1).

  Usage:
    powershell -ExecutionPolicy Bypass -File .\scripts\setup-ollama-portable.ps1
#>
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$OllamaDir = Join-Path $Root "ollama"
$ModelsDir = Join-Path $Root "data\ollama\models"
$CacheDir = Join-Path $Root "data\ollama\downloads"
$Version = "v0.30.0"
$BaseUrl = "https://github.com/ollama/ollama/releases/download/$Version"
$MainZip = "ollama-windows-amd64.zip"
$RocmZip = "ollama-windows-amd64-rocm.zip"

function Write-Step($msg) { Write-Host ""; Write-Host "==> $msg" -ForegroundColor Cyan }

New-Item -ItemType Directory -Force -Path $OllamaDir, $ModelsDir, $CacheDir | Out-Null

$exe = Join-Path $OllamaDir "ollama.exe"
if (Test-Path $exe) {
    Write-Host "ollama.exe already present at $exe — skipping download."
    & $exe --version
    exit 0
}

function Get-File($name) {
    $dest = Join-Path $CacheDir $name
    $minBytes = if ($name -eq $MainZip) { 500MB } else { 50MB }
    if ((Test-Path $dest) -and ((Get-Item $dest).Length -ge $minBytes)) {
        Write-Host "Using cached $dest"
        return $dest
    }
    if (Test-Path $dest) { Remove-Item $dest -Force }
    Write-Step "Downloading $name (large file, please wait)..."
    $url = "$BaseUrl/$name"
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        & $curl.Source -L -o $dest $url --progress-bar
        if ($LASTEXITCODE -ne 0) { throw "curl failed for $name (exit $LASTEXITCODE)" }
    } else {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    }
    if (-not (Test-Path $dest) -or (Get-Item $dest).Length -lt $minBytes) {
        throw "Download incomplete: $dest"
    }
    return $dest
}

function Expand-Zip($zipPath, $destDir) {
    Write-Step "Extracting $(Split-Path $zipPath -Leaf) -> $destDir"
    Expand-Archive -Path $zipPath -DestinationPath $destDir -Force
}

$mainPath = Get-File $MainZip
Expand-Zip $mainPath $OllamaDir

try {
    $rocmPath = Get-File $RocmZip
    Expand-Zip $rocmPath $OllamaDir
    Write-Host "ROCm GPU libraries merged (AMD Radeon)."
} catch {
    Write-Host "WARNING: ROCm zip failed — CPU/Vulkan may still work: $_" -ForegroundColor Yellow
}

if (-not (Test-Path $exe)) {
    throw "ollama.exe not found after extract. Check $OllamaDir"
}

Write-Step "Done"
& $exe --version
Write-Host ""
Write-Host "Start the server with:"
Write-Host "  powershell -ExecutionPolicy Bypass -File .\scripts\start-ollama.ps1"
Write-Host ""
Write-Host "Models directory: $ModelsDir"
