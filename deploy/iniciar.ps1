$ErrorActionPreference = "Stop"
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$venvPy = Join-Path $projectRoot "venv\Scripts\python.exe"
$ollamaDir = Join-Path $projectRoot "ollama"
$ollamaExe = Join-Path $ollamaDir "ollama.exe"
$ollamaModels = Join-Path $projectRoot "data\ollama\models"
$appPidFile = Join-Path $projectRoot "deploy\odysseus.pid"
$ollamaPidFile = Join-Path $projectRoot "deploy\ollama.pid"
$playitExe = "C:\Program Files\playit_gg\bin\playit.exe"

# Infra compartida con Razzia (playit + Caddy en 443)
$caddyScript = "D:\Archivos\Proyectos\Razzia\deploy\caddy\start-caddy.ps1"
$sitesFile = "D:\Archivos\Proyectos\Razzia\deploy\caddy\sites.txt"

$appPort = 7000
$ollamaPort = 11434

Set-Location $projectRoot

function Test-PortListening([int]$Port) {
    return [bool](Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
}

function Wait-ForPort([int]$Port, [int]$Seconds) {
    for ($i = 0; $i -lt $Seconds; $i++) {
        if (Test-PortListening $Port) { return $true }
        Start-Sleep -Seconds 1
    }
    return $false
}

Write-Host ""
Write-Host "=== Odysseus Hosting ===" -ForegroundColor Cyan
Write-Host ""

# 1. Ollama (portable, modelos en data\ollama\models)
Write-Host "[1/4] Iniciando Ollama..." -ForegroundColor Yellow
if (Test-PortListening $ollamaPort) {
    Write-Host "Ollama ya esta corriendo en el puerto $ollamaPort" -ForegroundColor Green
} elseif (Test-Path $ollamaExe) {
    $env:OLLAMA_MODELS = $ollamaModels
    $env:OLLAMA_HOST = "127.0.0.1:$ollamaPort"
    New-Item -ItemType Directory -Force -Path $ollamaModels | Out-Null

    $proc = Start-Process -FilePath $ollamaExe -ArgumentList "serve" `
        -WorkingDirectory $ollamaDir -WindowStyle Hidden -PassThru
    Set-Content -Path $ollamaPidFile -Value $proc.Id -Encoding ascii

    if (Wait-ForPort $ollamaPort 90) {
        Write-Host "Ollama OK (PID $($proc.Id), puerto $ollamaPort)" -ForegroundColor Green
    } else {
        Write-Host "Ollama no respondio en 90s. Revisa data\ollama." -ForegroundColor Red
    }
} else {
    Write-Host "No se encontro ollama\ollama.exe. Ejecuta scripts\setup-ollama-portable.ps1" -ForegroundColor Red
}

# 2. Odysseus (uvicorn)
Write-Host ""
Write-Host "[2/4] Iniciando Odysseus..." -ForegroundColor Yellow
if (Test-PortListening $appPort) {
    Write-Host "Odysseus ya esta corriendo en el puerto $appPort" -ForegroundColor Green
} elseif (-not (Test-Path $venvPy)) {
    Write-Host "No existe el venv. Ejecuta primero: launch-windows.ps1" -ForegroundColor Red
} else {
    $proc = Start-Process -FilePath $venvPy `
        -ArgumentList "-m", "uvicorn", "app:app", "--host", "127.0.0.1", "--port", "$appPort" `
        -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru
    Set-Content -Path $appPidFile -Value $proc.Id -Encoding ascii

    if (Wait-ForPort $appPort 60) {
        Write-Host "Odysseus OK (PID $($proc.Id)) en http://localhost:$appPort" -ForegroundColor Green
    } else {
        Write-Host "Odysseus tardo en responder. Revisa los logs en Launchpad." -ForegroundColor Yellow
    }
}

# 3. playit (tunel para acceso remoto)
Write-Host ""
Write-Host "[3/4] Iniciando playit..." -ForegroundColor Yellow
$playitService = Get-Service -Name "playitd" -ErrorAction SilentlyContinue
if ($playitService) {
    if ($playitService.Status -ne "Running") {
        Start-Service playitd
        Start-Sleep -Seconds 2
    }
    Write-Host "playit OK (servicio playitd activo)" -ForegroundColor Green
} elseif (Test-Path $playitExe) {
    $playitOut = & $playitExe start 2>&1 | Out-String
    if ($playitOut -match "started|running") {
        Write-Host "playit OK" -ForegroundColor Green
    } else {
        Write-Host $playitOut.Trim()
    }
} else {
    Write-Host "playit no encontrado. Instalalo desde https://playit.gg/download" -ForegroundColor Red
}

# 4. Caddy (SSL compartido con Razzia; enruta por dominio)
Write-Host ""
Write-Host "[4/4] Configurando Caddy (SSL)..." -ForegroundColor Yellow

$odysseusDomain = $null
if (Test-Path $sitesFile) {
    foreach ($line in Get-Content $sitesFile) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith("#")) { continue }
        $parts = $t -split "\s+"
        if ($parts.Count -ge 2 -and $parts[1] -eq "$appPort") {
            $odysseusDomain = $parts[0]
            break
        }
    }
}

if (-not $odysseusDomain) {
    Write-Host "Sin dominio para Odysseus todavia. Para acceso remoto:" -ForegroundColor Yellow
    Write-Host "  1. Crea un tunel nuevo en https://playit.gg (TCP, puerto local 443)" -ForegroundColor Yellow
    Write-Host "  2. Agrega en $sitesFile la linea:" -ForegroundColor Yellow
    Write-Host "     TU-DOMINIO.playit.gg $appPort" -ForegroundColor Yellow
    Write-Host "  3. Volve a iniciar Odysseus desde Launchpad" -ForegroundColor Yellow
} elseif (Test-Path $caddyScript) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $caddyScript
} else {
    Write-Host "No se encontro start-caddy.ps1 en Razzia" -ForegroundColor Red
}

Write-Host ""
Write-Host "Listo:" -ForegroundColor Green
Write-Host "  Local:  http://localhost:$appPort" -ForegroundColor White
if ($odysseusDomain) {
    Write-Host "  Remoto: https://$odysseusDomain  (desde tu celular)" -ForegroundColor White
}
Write-Host ""
