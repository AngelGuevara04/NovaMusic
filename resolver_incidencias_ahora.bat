@echo off
title Auto-Resolucion de Sugerencias e Incidencias - NovaMusic
echo Buscando sugerencias en el buzon de la app e incidencias en GitHub...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0auto_check_issues.ps1"
echo.
pause
