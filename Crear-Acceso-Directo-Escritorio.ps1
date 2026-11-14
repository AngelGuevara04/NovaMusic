# Script para restaurar el acceso directo de NovaMusic en el Escritorio después de formatear la PC
$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$exePath = Join-Path $projectDir "Instaladores\PC\NovaMusic-App\NovaMusic.exe"
$vbsPath = Join-Path $projectDir "Instaladores\PC\Iniciar-NovaMusic-PC.vbs"
$iconPath = Join-Path $projectDir "windows\runner\resources\app_icon.ico"
$desktopDir = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktopDir "NovaMusic.lnk"

$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($shortcutPath)

if (Test-Path $exePath) {
    $Shortcut.TargetPath = $exePath
    $Shortcut.WorkingDirectory = Split-Path -Parent $exePath
} else {
    $Shortcut.TargetPath = "wscript.exe"
    $Shortcut.Arguments = "`"$vbsPath`""
    $Shortcut.WorkingDirectory = Split-Path -Parent $vbsPath
}

if (Test-Path $iconPath) {
    $Shortcut.IconLocation = "$iconPath,0"
}
$Shortcut.Description = "NovaMusic - Aplicación de Música Personal"
$Shortcut.Save()

Write-Host "✅ Acceso directo 'NovaMusic' creado en el Escritorio correctamente." -ForegroundColor Green
