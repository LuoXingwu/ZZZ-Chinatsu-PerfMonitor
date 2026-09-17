# screenshot_desktop.ps1 - capture real desktop pixels to a PNG (ASCII only).
# Unlike a RenderTargetBitmap dump this captures the composited desktop, so
# layered/topmost pet windows are included exactly as the user sees them.
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\screenshot_desktop.ps1 -X 1300 -Y 830 -W 800 -H 620
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\screenshot_desktop.ps1 -All
param(
  [int]$X = 0, [int]$Y = 0, [int]$W = 0, [int]$H = 0, [switch]$All,
  [string]$Out = ''
)
$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
$shotDir = Join-Path $Root 'runtime\shots'
if (-not (Test-Path $shotDir)) { New-Item -ItemType Directory -Path $shotDir -Force | Out-Null }

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class ShotDpi {
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
  [DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int v);
  public static void Enable() {
    if (!SetProcessDpiAwarenessContext(new IntPtr(-4))) {
      if (SetProcessDpiAwareness(2) != 0) SetProcessDpiAwareness(1);
    }
  }
}
'@
[ShotDpi]::Enable()   # capture in physical pixels
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

if ($All -or $W -le 0 -or $H -le 0) {
  $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $X = $vs.X; $Y = $vs.Y; $W = $vs.Width; $H = $vs.Height
}
$bmp = New-Object System.Drawing.Bitmap($W, $H)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($X, $Y, 0, 0, (New-Object System.Drawing.Size($W, $H)))
$g.Dispose()
if (-not $Out) { $Out = Join-Path $shotDir ("{0}_desktop_{1}x{2}_at_{3}_{4}.png" -f (Get-Date -Format 'HHmmss'), $W, $H, $X, $Y) }
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output ("captured {0}x{1} at {2},{3} -> {4}" -f $W, $H, $X, $Y, $Out)
