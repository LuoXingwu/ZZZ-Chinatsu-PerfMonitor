' ZZZ Sunna PerfMonitor launcher (v1)
' ASCII-only on purpose: this project lives under a non-ASCII path, and a
' VBS file's own text encoding would otherwise have to match the system
' codepage. The pet path is therefore derived from the location of this
' script at runtime instead of being written as a literal.
Option Explicit
Dim fso, sh, here, appDir, target
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
here = fso.GetParentFolderName(WScript.ScriptFullName)
appDir = fso.GetParentFolderName(here)
target = fso.BuildPath(appDir, "pet.ps1")
sh.CurrentDirectory = appDir
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Sta -File """ & target & """", 0, False
