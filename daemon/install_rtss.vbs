' ZZZ Sunna PerfMonitor - RTSS one-click installer entry (double-click me)
' ASCII-only on purpose: the project path is non-ASCII, so the target is
' derived from this script's own location instead of a hard coded literal.
Option Explicit
Dim fso, sh, here, target
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
here = fso.GetParentFolderName(WScript.ScriptFullName)
target = fso.BuildPath(here, "install_rtss.ps1")
sh.CurrentDirectory = here
' window style 1 = visible console so the user can see progress, wait = True
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & target & """", 1, True
