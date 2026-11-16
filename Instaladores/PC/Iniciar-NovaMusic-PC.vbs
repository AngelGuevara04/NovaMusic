' ===================================================
' NovaMusic PC Launcher - Inicio Silencioso y Confiable
' ===================================================
Option Explicit

Dim WshShell, fso, strDir, pythonExe, url, http, i, ready

Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
strDir = fso.GetParentFolderName(WScript.ScriptFullName)
WshShell.CurrentDirectory = strDir
url = "http://127.0.0.1:8085"

' 1. Detectar ejecutable de Python
pythonExe = "python"
If fso.FileExists("C:\Users\ajgm1\AppData\Local\Programs\Python\Python314\python.exe") Then
    pythonExe = "C:\Users\ajgm1\AppData\Local\Programs\Python\Python314\python.exe"
ElseIf fso.FileExists("C:\Users\ajgm1\AppData\Local\Programs\Python\Python313\python.exe") Then
    pythonExe = "C:\Users\ajgm1\AppData\Local\Programs\Python\Python313\python.exe"
ElseIf fso.FileExists("C:\Users\ajgm1\AppData\Local\Programs\Python\Python312\python.exe") Then
    pythonExe = "C:\Users\ajgm1\AppData\Local\Programs\Python\Python312\python.exe"
End If

' 2. Comprobar si ya está activo
ready = False
On Error Resume Next
Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")
http.setTimeouts 500, 500, 500, 500
http.Open "GET", url, False
http.Send
If Err.Number = 0 Then
    If http.Status = 200 Then
        ready = True
    End If
End If
Err.Clear
On Error GoTo 0

' 3. Si no está activo, iniciarlo completamente invisible en segundo plano
If Not ready Then
    WshShell.Run """" & pythonExe & """ server.py", 0, False
    
    ' Esperar hasta que responda (máximo 6 segundos)
    For i = 1 To 15
        WScript.Sleep 400
        On Error Resume Next
        Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")
        http.setTimeouts 400, 400, 400, 400
        http.Open "GET", url, False
        http.Send
        If Err.Number = 0 Then
            If http.Status = 200 Then
                ready = True
                Exit For
            End If
        End If
        Err.Clear
        On Error GoTo 0
    Next
End If

' 4. Abrir en modo aplicación nativa de escritorio (sin barras de navegador y permitiendo reproducción remota sin clic previo)
On Error Resume Next
WshShell.Run "msedge.exe --autoplay-policy=no-user-gesture-required --app=" & url, 3, False
If Err.Number <> 0 Then
    Err.Clear
    WshShell.Run "chrome.exe --autoplay-policy=no-user-gesture-required --app=" & url, 3, False
    If Err.Number <> 0 Then
        Err.Clear
        WshShell.Run url, 3, False
    End If
End If

Set http = Nothing
Set fso = Nothing
Set WshShell = Nothing
