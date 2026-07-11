$ErrorActionPreference = "SilentlyContinue"
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$appPidFile = Join-Path $projectRoot "deploy\odysseus.pid"
$ollamaPidFile = Join-Path $projectRoot "deploy\ollama.pid"

Set-Location $projectRoot

function Stop-ByPidFile([string]$PidFile) {
    if (Test-Path $PidFile) {
        $savedPid = (Get-Content $PidFile -Raw).Trim()
        if ($savedPid) {
            Stop-Process -Id ([int]$savedPid) -Force -ErrorAction SilentlyContinue
        }
        Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
    }
}

function Stop-ByPort([int]$Port) {
    Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
        ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
}

Write-Host ""
Write-Host "=== Deteniendo Odysseus ===" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1/3] Deteniendo Odysseus (uvicorn)..." -ForegroundColor Yellow
Stop-ByPidFile $appPidFile
Stop-ByPort 7000
Write-Host "Odysseus detenido" -ForegroundColor Green

Write-Host ""
Write-Host "[2/3] Deteniendo Ollama..." -ForegroundColor Yellow
Stop-ByPidFile $ollamaPidFile
Stop-ByPort 11434
Get-Process ollama -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Write-Host "Ollama detenido" -ForegroundColor Green

Write-Host ""
Write-Host "[3/3] playit y Caddy se dejan corriendo (compartidos con Razzia)." -ForegroundColor DarkGray
Write-Host ""
Write-Host "Todo detenido." -ForegroundColor Green
Write-Host ""
