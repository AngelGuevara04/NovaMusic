@echo off
setlocal
cd /d "%~dp0"
title NovaMusic PC

:: Detectar ejecutable de Python
set "PYTHON_EXE=pythonw"
if exist "C:\Users\ajgm1\AppData\Local\Programs\Python\Python314\pythonw.exe" set "PYTHON_EXE=C:\Users\ajgm1\AppData\Local\Programs\Python\Python314\pythonw.exe"
if exist "C:\Users\ajgm1\AppData\Local\Programs\Python\Python313\pythonw.exe" set "PYTHON_EXE=C:\Users\ajgm1\AppData\Local\Programs\Python\Python313\pythonw.exe"
if exist "C:\Users\ajgm1\AppData\Local\Programs\Python\Python312\pythonw.exe" set "PYTHON_EXE=C:\Users\ajgm1\AppData\Local\Programs\Python\Python312\pythonw.exe"

:: Comprobar si ya está corriendo el servidor
powershell -NoProfile -Command "try { (Invoke-WebRequest -Uri 'http://127.0.0.1:8085' -UseBasicParsing -TimeoutSec 1).StatusCode } catch { exit 1 }" >nul 2>&1
if errorlevel 1 (
    start "" /b "%PYTHON_EXE%" "%~dp0server.py"
    timeout /t 2 /nobreak >nul
)

:: Abrir en modo aplicación nativa
start "" msedge.exe --app=http://127.0.0.1:8085 2>nul || start "" chrome.exe --app=http://127.0.0.1:8085 2>nul || start "" http://127.0.0.1:8085
exit /b 0
