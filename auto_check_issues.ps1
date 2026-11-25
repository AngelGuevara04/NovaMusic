param (
    [switch]$Silent
)

$ErrorActionPreference = "Continue"
$env:JAVA_HOME = "C:\src\jdk-17"
$env:ANDROID_HOME = "C:\src\android-sdk"
$env:ANDROID_SDK_ROOT = "C:\src\android-sdk"
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User") + ";C:\src\flutter\bin;C:\src\jdk-17\bin;C:\src\android-sdk\cmdline-tools\latest\bin;C:\src\android-sdk\platform-tools"

$repo = "AngelGuevara04/NovaMusic"
$projectDir = "c:\Users\ajgm1\.gemini\antigravity\scratch\NovaMusic"
$conversationId = "6b67ec46-549a-4507-814f-0e9147ae60ed"
$agentApi = "C:\Users\ajgm1\.gemini\antigravity\bin\agentapi.bat"
$antigravityExe = "$env:LOCALAPPDATA\Programs\Antigravity\Antigravity.exe"

$supabaseUrl = "https://pqvlwcqfjqrukgvwfhnh.supabase.co/rest/v1/app_suggestions?status=eq.pending&order=created_at.asc"
$supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBxdmx3Y3FmanFydWtndndmaG5oIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI5MjQ5MzYsImV4cCI6MjA5ODUwMDkzNn0.F1AYU6R5ri3DnZEdfsHA9dTRbZXEpNdjalZWd5nfWp8"

if ($Silent) {
    # Esperar unos segundos al iniciar Windows para asegurar conexión Wi-Fi
    Start-Sleep -Seconds 20
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  NOVAMUSIC - DETECTOR AUTOMATICO DE INCIDENCIAS Y BUZON  " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Consultar GitHub Issues abiertas en AngelGuevara04/NovaMusic
$ghIssues = @()
try {
    $ghUrl = "https://api.github.com/repos/$repo/issues?state=open&per_page=30"
    $rawGh = Invoke-RestMethod -Uri $ghUrl -Headers @{ "User-Agent" = "NovaMusic-AutoUpdater" } -TimeoutSec 15
    if ($rawGh) {
        foreach ($item in $rawGh) {
            if (-not $item.pull_request) {
                $ghIssues += $item
            }
        }
    }
} catch {
    Write-Host "Aviso: No se pudo consultar GitHub Issues: $_" -ForegroundColor Yellow
}

# 2. Consultar Buzon de Sugerencias en Supabase (tabla app_suggestions con status=pending)
$novaSuggestions = @()
try {
    $headers = @{
        "apikey" = $supabaseKey
        "Authorization" = "Bearer $supabaseKey"
    }
    $rawSupa = Invoke-RestMethod -Uri $supabaseUrl -Headers $headers -TimeoutSec 15
    if ($rawSupa) {
        foreach ($row in $rawSupa) {
            $msg = [string]$row.message
            $type = [string]$row.type
            # Excluir sugerencias que pertenecen a AppParaMiAmors
            if ($msg -notmatch "^\[AppParaMiAmors\]" -and $type -ne "capitulo_caido") {
                $novaSuggestions += $row
            }
        }
    }
} catch {
    Write-Host "Aviso: No se pudo consultar Supabase app_suggestions: $_" -ForegroundColor Yellow
}

$totalPending = $ghIssues.Count + $novaSuggestions.Count

if ($totalPending -eq 0) {
    Write-Host "No hay nuevas incidencias en GitHub ni sugerencias pendientes en NovaMusic." -ForegroundColor Green
    exit 0
}

Write-Host "¡Se detectaron $($ghIssues.Count) incidencia(s) en GitHub y $($novaSuggestions.Count) sugerencia(s) en el buzon de NovaMusic!" -ForegroundColor Yellow

# Construir reporte detallado para Antigravity
$reportLines = @()
$reportLines += "[AUTO-DETECCION AL ENCENDER LA PC - NOVAMUSIC]"
$reportLines += "Se han detectado $totalPending reporte(s) / sugerencia(s) pendientes para NovaMusic ($projectDir)."
$reportLines += ""

if ($ghIssues.Count -gt 0) {
    $reportLines += "=== INCIDENCIAS ABIERTAS EN GITHUB ($repo) ==="
    foreach ($issue in $ghIssues) {
        $reportLines += "--------------------------------------------------------"
        $reportLines += "- Issue #$($issue.number): $($issue.title)"
        $reportLines += "- Autor: $($issue.user.login) | Fecha: $($issue.created_at)"
        $reportLines += "- Descripcion:"
        $reportLines += "$($issue.body)"
    }
    $reportLines += ""
}

if ($novaSuggestions.Count -gt 0) {
    $reportLines += "=== SUGERENCIAS / REPORTES DESDE LA APP (Supabase -> app_suggestions) ==="
    foreach ($sug in $novaSuggestions) {
        $reportLines += "--------------------------------------------------------"
        $reportLines += "- ID Supabase: $($sug.id)"
        $reportLines += "- Usuario: $($sug.username) | Tipo: $($sug.type) | Dispositivo: $($sug.device_info) | Version: $($sug.app_version)"
        $reportLines += "- Mensaje: $($sug.message)"
    }
    $reportLines += ""
}

$reportLines += "--------------------------------------------------------"
$reportLines += "=== INSTRUCCIONES AUTOMATICAS PARA RESOLVER Y PUBLICAR EL PARCHE REMOTO ==="
$reportLines += '1. Analiza cada incidencia/sugerencia listada arriba e implementa la solucion o mejora en el codigo de c:\Users\ajgm1\.gemini\antigravity\scratch\NovaMusic.'
$reportLines += '2. Incrementa el numero de version (+N) tanto en pubspec.yaml como en lib/services/updater_service.dart (currentVersion).'
$reportLines += '3. Compila la version Web/PC con C:\src\flutter\bin\flutter.bat build web --release --no-tree-shake-icons, actualiza Instaladores\PC\NovaMusic-PC y recompila NovaMusic.exe con python -m PyInstaller NovaMusic.spec --noconfirm.'
$reportLines += '4. Compila el APK de Android con C:\src\flutter\bin\flutter.bat build apk --release --no-tree-shake-icons --android-skip-build-dependency-validation, haz git add -A, git commit, git push origin main y publica el Release remoto con gh release create v1.0.0+XX build\app\outputs\flutter-apk\app-release.apk Instaladores\PC\NovaMusic-PC-Escritorio-v1.0.0+XX.zip --repo AngelGuevara04/NovaMusic para que todos los dispositivos se actualicen de forma remota (OTA).'
$reportLines += '5. Marca las sugerencias de Supabase como resueltas (status = completed mediante PATCH a https://pqvlwcqfjqrukgvwfhnh.supabase.co/rest/v1/app_suggestions?id=eq.<ID>) y cierra las Issues de GitHub con gh issue close <num> --repo AngelGuevara04/NovaMusic --comment "Resuelto automaticamente en la nueva version."'

$promptText = $reportLines -join "`n"

# Guardar respaldo legible del reporte en el proyecto
$reportFile = Join-Path $projectDir "INCIDENCIAS_PENDIENTES.md"
Set-Content -Path $reportFile -Value $promptText -Encoding UTF8

# Abrir la ventana de Antigravity en el proyecto NovaMusic si no esta abierta
if (Test-Path $antigravityExe) {
    Start-Process -FilePath $antigravityExe -ArgumentList "`"$projectDir`""
    Start-Sleep -Seconds 15
}

# Enviar mensaje directo a la conversacion del proyecto en Antigravity usando agentapi.bat
if (Test-Path $agentApi) {
    Write-Host "Enviando instrucciones automaticas a la conversacion de NovaMusic en Antigravity..." -ForegroundColor Cyan
    & $agentApi send-message --title="[Auto-Resolucion] Sugerencias e Incidencias de NovaMusic" $conversationId $promptText
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Creando nueva conversacion automatica en Antigravity..." -ForegroundColor Yellow
        & $agentApi new-conversation --title="[Auto-Resolucion] Sugerencias e Incidencias de NovaMusic" $promptText
    }
    Write-Host "¡Notificacion enviada con exito a Antigravity!" -ForegroundColor Green
} else {
    Write-Host "No se encontro agentapi.bat en $agentApi" -ForegroundColor Red
}
