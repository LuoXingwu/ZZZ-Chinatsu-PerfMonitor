# pet_info.ps1 - ZZZ Sunna PerfMonitor diagnostics (ASCII only: no BOM needed)
# Reports the pet process, every WpmV1 component window, and the log tail.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\pet_info.ps1
param([int]$Tail = 12)
$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot

# Without this the whole script runs DPI-unaware and every GetWindowRect value
# would come back divided by the monitor scale (a v4-era trap).
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class PetInfoDpi {
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
  [DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int v);
  public static void Enable() {
    if (!SetProcessDpiAwarenessContext(new IntPtr(-4))) {
      if (SetProcessDpiAwareness(2) != 0) SetProcessDpiAwareness(1);
    }
  }
}
'@
[PetInfoDpi]::Enable()

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class PetInfo {
  public delegate bool Cb(IntPtr h, IntPtr d);
  [DllImport("user32.dll")] public static extern bool EnumWindows(Cb c, IntPtr d);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  public struct R { public int L, T, Rr, B; }
  public static List<string> Windows(string prefix) {
    List<string> o = new List<string>();
    EnumWindows(delegate(IntPtr h, IntPtr d) {
      if (!IsWindowVisible(h)) return true;
      StringBuilder t = new StringBuilder(128);
      GetWindowTextW(h, t, 128);
      if (t.Length > 0 && t.ToString().StartsWith(prefix)) {
        R r; GetWindowRect(h, out r);
        uint p; GetWindowThreadProcessId(h, out p);
        int ex = GetWindowLong(h, -20);
        o.Add(string.Format("{0,-14} pid={1,-7} rect={2},{3} {4}x{5} topmost={6} layered={7} notab={8}",
          t.ToString(), p, r.L, r.T, r.Rr - r.L, r.B - r.T,
          ((ex & 0x8) != 0), ((ex & 0x80000) != 0), ((ex & 0x80) != 0)));
      }
      return true;
    }, IntPtr.Zero);
    return o;
  }
}
'@

Write-Output "=== process ==="
$found = $false
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -like '*pet.ps1*' } |
  ForEach-Object {
    $found = $true
    $p = Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
    $mem = 0; if ($p) { $mem = [int]($p.WorkingSet64 / 1MB) }
    Write-Output ("pid={0} WS={1}MB cmd={2}" -f $_.ProcessId, $mem, $_.CommandLine.Trim())
  }
if (-not $found) { Write-Output 'NO pet.ps1 process running' }

Write-Output ""
Write-Output "=== v5 component windows ==="
$wins = [PetInfo]::Windows('WpmV1|')
if ($wins.Count -eq 0) { Write-Output '(none)' } else { $wins | ForEach-Object { Write-Output $_ } }

Write-Output ""
$pidFile = Join-Path $Root 'runtime\pet.pid'
if (Test-Path $pidFile) { Write-Output ("=== pid file: " + (Get-Content $pidFile -Raw).Trim()) } else { Write-Output '=== pid file: (none)' }
Write-Output "=== log tail ==="
$log = Join-Path $Root 'runtime\pet.log'
if (Test-Path $log) { Get-Content $log -Tail $Tail } else { Write-Output '(no log)' }
