' Double-click this file to open the Survival Sandbox launcher without a console window.
Option Explicit
Dim shell, scriptDir, command
Set shell = CreateObject("Wscript.Shell")
scriptDir = Replace(WScript.ScriptFullName, WScript.ScriptName, "")
command = "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File """ & scriptDir & "launcher.ps1"""
' Window style 0 keeps the console hidden. launcher.ps1 then shows the form.
shell.Run command, 0, False
