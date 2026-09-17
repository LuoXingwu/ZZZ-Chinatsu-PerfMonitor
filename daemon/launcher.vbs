' ZZZ Sunna PerfMonitor daemon launcher (run by the elevated scheduled task)
' ASCII-only on purpose: the project path is non-ASCII, so the target is
' derived from this script's own location instead of a hard coded literal.
Option Explicit
Dim fso, sh, here, target
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
here = fso.GetParentFolderName(WScript.ScriptFullName)
target = fso.BuildPath(here, "daemon.ps1")
sh.CurrentDirectory = here
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & target & """", 0, False
