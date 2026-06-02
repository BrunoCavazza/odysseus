#Requires -Version 5.1
<#
  Run portable Ollama from ./ollama with models in ./data/ollama/models.

  Usage:
    powershell -ExecutionPolicy Bypass -File .\scripts\start-ollama.ps1
    powershell -ExecutionPolicy Bypass -File .\scripts\start-ollama.ps1 -Pull qwen2.5:3b-instruct
#>
param(
    [string]$Pull = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$OllamaDir = Join-Path $Root "ollama"
$Exe = Join-Path $OllamaDir "ollama.exe"
$ModelsDir = Join-Path $Root "data\ollama\models"
$ApiUrl = "http://127.0.0.1:11434"

if (-not (Test-Path $Exe)) {
    Write-Host "ollama.exe not found. Run setup first:" -ForegroundColor Yellow
    Write-Host "  powershell -ExecutionPolicy Bypass -File .\scripts\setup-ollama-portable.ps1"
    exit 1
}

New-Item -ItemType Directory -Force -Path $ModelsDir | Out-Null

$env:OLLAMA_MODELS = $ModelsDir
$env:OLLAMA_HOST = "127.0.0.1:11434"
$env:PATH = "$OllamaDir;$env:PATH"

Set-Location $OllamaDir

function Test-OllamaUp {
    try {
        $r = Invoke-WebRequest -Uri $ApiUrl -UseBasicParsing -TimeoutSec 2
        return $r.StatusCode -eq 200
    } catch {
        return $false
    }
}

function Wait-OllamaUp([int]$Seconds = 90) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-OllamaUp) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

$bgProc = $null
$weStarted = $false

if (-not (Test-OllamaUp)) {
    Write-Host "Starting Ollama server..." -ForegroundColor Cyan
    $bgProc = Start-Process -FilePath $Exe -ArgumentList "serve" -WorkingDirectory $OllamaDir -WindowStyle Hidden -PassThru
    $weStarted = $true
    if (-not (Wait-OllamaUp)) {
        if ($bgProc -and -not $bgProc.HasExited) { Stop-Process -Id $bgProc.Id -Force -ErrorAction SilentlyContinue }
        throw "Ollama did not start on $ApiUrl within 90s. Check data/ollama or run setup-ollama-portable.ps1 again."
    }
    Write-Host "Ollama server is up." -ForegroundColor Green
}

if ($Pull) {
    Write-Host "Pulling model: $Pull" -ForegroundColor Cyan
    & $Exe pull $Pull
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

# If we only started Ollama for pull, restart in foreground so Ctrl+C stops the server.
if ($weStarted -and $bgProc -and -not $bgProc.HasExited) {
    Stop-Process -Id $bgProc.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

if (Test-OllamaUp) {
    Write-Host ""
    Write-Host "Ollama is already running on port 11434." -ForegroundColor Yellow
    Write-Host "API:    $ApiUrl/v1"
    Write-Host "Models: $ModelsDir"
    if ($Pull) { Write-Host "Pull finished. Leave the other Ollama process running." }
    exit 0
}

Write-Host ""
Write-Host "Ollama API: $ApiUrl" -ForegroundColor Green
Write-Host "Models:     $ModelsDir"
Write-Host "Odysseus:   $ApiUrl/v1"
Write-Host "Press Ctrl+C to stop."
Write-Host ""

& $Exe serve
