# check_system_load.ps1 - "is anything else slowing my game down?" (ASCII only)
#
# Answers the question that follows a mystery FPS drop: which always-resident
# processes are involved, are they elevated, is more than one pet running, are
# the pet windows still topmost, and what is the GPU doing right now.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\check_system_load.ps1
$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class SL {
  public delegate bool Cb(IntPtr h, IntPtr d);
  [DllImport("user32.dll")] public static extern bool EnumWindows(Cb c, IntPtr d);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(uint a, bool i, int p);
  [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
  public static List<string> Wins() {
    List<string> o = new List<string>();
    EnumWindows(delegate(IntPtr h, IntPtr d) {
      StringBuilder t = new StringBuilder(128); GetWindowTextW(h, t, 128);
      string s = t.ToString();
      if (s.StartsWith("WpmV1|")) {
        int ex = GetWindowLong(h, -20);
        o.Add(string.Format("{0,-14} topmost={1} ENABLED={2} (ENABLED=False means no mouse input reaches it)",
          s.Substring(6), ((ex & 0x8) != 0) ? "YES" : "no ", IsWindowEnabled(h) ? "yes" : "NO "));
      }
      return true;
    }, IntPtr.Zero);
    return o;
  }
  public static string Foreground() {
    IntPtr h = GetForegroundWindow();
    StringBuilder t = new StringBuilder(128); GetWindowTextW(h, t, 128);
    StringBuilder c = new StringBuilder(128); GetClassNameW(h, c, 128);
    return string.Format("title='{0}' class={1}", t.ToString(), c.ToString());
  }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R rc);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [StructLayout(LayoutKind.Sequential)] public struct R { public int L, T, Rr, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  // which window would actually receive a click at each component's centre
  public static List<string> HitTest() {
    List<string> o = new List<string>();
    foreach (string key in new string[] { "pet", "panel", "guitar", "easel", "bchan" }) {
      EnumWindows(delegate(IntPtr h, IntPtr d) {
        StringBuilder t = new StringBuilder(128); GetWindowTextW(h, t, 128);
        if (t.ToString() == "WpmV1|" + key) {
          R r; GetWindowRect(h, out r);
          int cx = r.L + (r.Rr - r.L) / 2, cy = r.T + (r.B - r.T) / 2;
          IntPtr hit = WindowFromPoint(new POINT { X = cx, Y = cy });
          StringBuilder ht = new StringBuilder(128); GetWindowTextW(hit, ht, 128);
          o.Add(string.Format("{0,-7} centre=({1},{2}) -> click would go to '{3}'", key, cx, cy, ht.ToString()));
        }
        return true;
      }, IntPtr.Zero);
    }
    return o;
  }
  public static bool CanTerminate(int pid) {
    IntPtr h = OpenProcess(0x0001, false, pid);
    if (h == IntPtr.Zero) return false;
    CloseHandle(h);
    return true;
  }
}
'@

Write-Output "=== 1. pet processes ==="
$pets = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -like '*pet.ps1*' })
if ($pets.Count -eq 0) {
  Write-Output "  (not running)"
} elseif ($pets.Count -eq 1) {
  Write-Output ("  OK single instance pid=" + $pets[0].ProcessId)
} else {
  Write-Output ("  !! " + $pets.Count + " pet instances (expected exactly 1):")
  $pets | ForEach-Object { Write-Output ("     pid=" + $_.ProcessId) }
}
foreach ($pp in $pets) {
  $pr = Get-Process -Id $pp.ProcessId -ErrorAction SilentlyContinue
  if ($pr) {
    $c0 = $pr.CPU
    Start-Sleep -Milliseconds 1500
    $pr.Refresh()
    $c1 = $pr.CPU
    $pct = (($c1 - $c0) / 1.5) * 100
    Write-Output ("     pid={0} WS={1}MB CPU={2:N1}% of one core threads={3}" -f $pp.ProcessId, [int]($pr.WorkingSet64 / 1MB), $pct, $pr.Threads.Count)
  }
}

Write-Output ""
Write-Output "=== 2. always-resident processes that matter for FPS (leftovers / elevation) ==="
$names = 'PresentMon_x64', 'PresentMon', 'PresentMon1', 'nvidia-smi', 'RTSS', 'RTSSHooksLoader64', 'EncoderServer'
$found = $false
foreach ($n in $names) {
  Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object {
    $script:found = $true
    $can = 'yes'
    if (-not [SL]::CanTerminate($_.Id)) { $can = 'NO (elevated/protected)' }
    Write-Output ("  {0,-20} pid={1,-7} CPU={2,7:N1}s WS={3,4}MB you-can-stop-it={4}" -f $_.ProcessName, $_.Id, $_.CPU, [int]($_.WorkingSet64 / 1MB), $can)
  }
}
if (-not $found) { Write-Output "  (none)" }
Write-Output "  note: RTSS / EncoderServer belong to RTSS itself and stay after the pet exits"
Write-Output "        (normal, but you may exit them); PresentMon / nvidia-smi here would be leftovers"
Write-Output "        (the pet never launches either of them)."

Write-Output ""
Write-Output "=== 3. pet windows: topmost / enabled (a disabled window gets NO mouse input) ==="
$w = [SL]::Wins()
if ($w.Count -eq 0) { Write-Output "  (no pet windows)" } else { $w | ForEach-Object { Write-Output ("  " + $_) } }
Write-Output ("  foreground window: " + [SL]::Foreground())
Write-Output "  what a click at each component centre would hit:"
[SL]::HitTest() | ForEach-Object { Write-Output ("    " + $_) }

Write-Output ""
Write-Output "=== 4. GPU utilization right now (includes the desktop itself) ==="
$smi = Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'
if (Test-Path $smi) {
  for ($i = 1; $i -le 3; $i++) {
    $v = & $smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader
    Write-Output ("  sample " + $i + ": " + $v)
    Start-Sleep -Milliseconds 800
  }
  Write-Output "  (idle desktop is normally 0-5%; compare this while a game runs)"
} else { Write-Output "  nvidia-smi not found (non-NVIDIA GPU)" }

Write-Output ""
Write-Output "=== 5. how to read this ==="
Write-Output "  game slow, and exiting the pet does not help  -> look at section 2 (leftover/elevated"
Write-Output "    processes, RTSS OSD or frame limiter) and at whether the game was already forced into"
Write-Output "    windowed/borderless mode (restarting the game restores exclusive fullscreen)."
Write-Output "  to rule the pet out entirely: right-click -> cancel topmost (remembered), or set"
Write-Output "    untopInGame = true in config.json (automatically drops topmost while a game is detected)."
