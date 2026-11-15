@echo off
REM Se ejecuta silenciosamente al iniciar Windows para revisar sugerencias e incidencias de NovaMusic
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0auto_check_issues.ps1" -Silent
