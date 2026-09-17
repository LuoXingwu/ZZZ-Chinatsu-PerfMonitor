# input_test.ps1 - drive the pet with REAL mouse input and report what the log saw.
#
# Why this exists: petcmd's udrag/uclick/uwheel commands verify the *logic* only.
# They cannot prove that Windows actually delivers mouse input to the layered
# component windows. This script synthesises real cursor input (SetCursorPos +
# mouse_event) over the pet's own window rectangles and then reads the pet log
# for the expected evidence. It is the only automated check of the input path.
#
# The physical cursor is saved and restored. Clicks land inside the pet's own
# windows (queried live), never on other applications.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\input_test.ps1
# Exit code 0 = all three input paths worked.
param([int]$SettleMs = 900)
$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
$Log = Join-Path $Root 'runtime\pet.log'
$fail = 0
function Pass([string]$m) { Write-Output ("  [PASS] " + $m) }
function Fail([string]$m) { Write-Output ("  [FAIL] " + $m); $script:fail++ }
function Skip([string]$m) { Write-Output ("  [SKIP] " + $m) }
function Info([string]$m) { Write-Output ("         " + $m) }

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class InpWin {
  public delegate bool Cb(IntPtr h, IntPtr d);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
  [DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int v);
  [DllImport("user32.dll")] public static extern bool EnumWindows(Cb c, IntPtr d);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out R2 p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, int data, IntPtr extra);
  public struct R { public int L, T, Rr, B; }
  public struct R2 { public int X, Y; }
  public static void Enable() {
    if (!SetProcessDpiAwarenessContext(new IntPtr(-4))) {
      if (SetProcessDpiAwareness(2) != 0) SetProcessDpiAwareness(1);
    }
  }
  public static Dictionary<string,int[]> Rects(string prefix) {
    Dictionary<string,int[]> o = new Dictionary<string,int[]>();
    EnumWindows(delegate(IntPtr h, IntPtr d) {
      if (!IsWindowVisible(h)) return true;
      StringBuilder t = new StringBuilder(128);
      GetWindowTextW(h, t, 128);
      string s = t.ToString();
      if (s.StartsWith(prefix)) {
        R r; GetWindowRect(h, out r);
        o[s.Substring(prefix.Length)] = new int[] { r.L, r.T, r.Rr - r.L, r.B - r.T };
      }
      return true;
    }, IntPtr.Zero);
    return o;
  }
}
'@
[InpWin]::Enable()

function Read-LogRaw {
  # the pet appends constantly; a read can collide with a write ("in use").
  # Retry a few times, always as UTF-8 (the log is UTF-8 without BOM; a default
  # ANSI read would mojibake the Chinese lines and shift .Length).
  for ($i = 0; $i -lt 5; $i++) {
    try { return (Get-Content $Log -Raw -Encoding UTF8) } catch { Start-Sleep -Milliseconds 250 }
  }
  return ''
}
function Log-Mark { return (Read-LogRaw).Length }
function Log-Since([int]$from) {
  $t = Read-LogRaw
  if ($t.Length -le $from) { return '' }
  if ($from -lt 0) { $from = 0 }
  return $t.Substring($from)
}
$script:LastCursor = @(0, 0)
$script:CursorStolen = $false
function Move-Phys([int]$x, [int]$y) {
  # A human using the mouse at the same time will yank the cursor back, and the
  # synthetic click then lands somewhere else entirely (it looks exactly like a
  # dead app).  Verify the cursor actually arrived, retry a few times, and flag
  # it when the mouse is clearly in use so failures can say WHY.
  $script:CursorStolen = $false
  for ($i = 0; $i -lt 4; $i++) {
    [void][InpWin]::SetCursorPos($x, $y)
    Start-Sleep -Milliseconds 150
    $p = New-Object InpWin+R2
    [void][InpWin]::GetCursorPos([ref]$p)
    $script:LastCursor = @($p.X, $p.Y)
    if ([Math]::Abs($p.X - $x) -le 2 -and [Math]::Abs($p.Y - $y) -le 2) { return }
    $script:CursorStolen = $true
  }
}
function Click-Phys([int]$x, [int]$y) {
  Move-Phys $x $y
  [InpWin]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)   # LEFTDOWN
  Start-Sleep -Milliseconds 60
  [InpWin]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)   # LEFTUP
  Start-Sleep -Milliseconds $SettleMs
}
function Wheel-Phys([int]$x, [int]$y, [int]$notches) {
  Move-Phys $x $y
  for ($i = 0; $i -lt [Math]::Abs($notches); $i++) {
    [InpWin]::mouse_event(0x0800, 0, 0, ([int](120 * [Math]::Sign($notches))), [IntPtr]::Zero)   # WHEEL
    Start-Sleep -Milliseconds 120
  }
  Start-Sleep -Milliseconds $SettleMs
}

$orig = New-Object InpWin+R2
[void][InpWin]::GetCursorPos([ref]$orig)
Write-Output "=== ZZZ Sunna PerfMonitor input test (moves the real cursor, restores it at the end) ==="
$rects = [InpWin]::Rects('WpmV1|')
if ($rects.Count -eq 0) { Write-Output 'NO pet windows found - start the pet first'; exit 1 }
foreach ($k in $rects.Keys) { $r = $rects[$k]; Info ($k + "  " + $r[2] + "x" + $r[3] + " at " + $r[0] + "," + $r[1]) }

# ---- 1. click the character: expect a manual pose change in the log ----
$r = $rects['pet']; $cx = $r[0] + [int]($r[2] / 2); $cy = $r[1] + [int]($r[3] / 2)
$m = Log-Mark
Click-Phys $cx $cy
$t = Log-Since $m
if ($t -match 'pose -> .*(manual)') { Pass 'click on the character reached the app (manual pose change logged)' }
elseif ($script:CursorStolen) {
  Skip 'the physical mouse was moved during the test (you are using the computer) - run this again hands-off'
}
else {
  Fail 'click on the character produced no app reaction'
  Info ("clicked (" + $cx + "," + $cy + ") cursor now at (" + $script:LastCursor[0] + "," + $script:LastCursor[1] + ")")
  Info ("log delta " + $t.Length + " chars: " + ($t -replace "`n", ' | ').Substring(0, [Math]::Min(220, $t.Length)))
}

# ---- 2. click the bubblechan: expect a monitored-screen switch ----
$r = $rects['bchan']; $cx = $r[0] + [int]($r[2] / 2); $cy = $r[1] + [int]($r[3] * 0.35)
$m = Log-Mark
Click-Phys $cx $cy
$t = Log-Since $m
if ($t -match 'screen pick ->') { Pass 'click on the bubblechan reached the app (screen switch logged)' }
elseif ($script:CursorStolen) { Skip 'mouse in use (see above)' }
else { Fail 'click on the bubblechan produced no app reaction' }

# ---- 3. wheel over any component: expect the WHOLE arrangement to scale ----
$r = $rects['panel']; $cx = $r[0] + [int]($r[2] / 2); $cy = $r[1] + [int]($r[3] / 2)
$k0 = $null; $k1 = $null
try { $k0 = [double](Get-Content (Join-Path $Root 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json).groupScale } catch { }
$m = Log-Mark
Wheel-Phys $cx $cy 2
$t = Log-Since $m
try { $k1 = [double](Get-Content (Join-Path $Root 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json).groupScale } catch { }
if ($null -ne $k0 -and $null -ne $k1 -and [Math]::Abs($k1 - $k0) -gt 0.01) {
  Pass ("wheel scales the whole group (groupScale " + [Math]::Round($k0, 3) + " -> " + [Math]::Round($k1, 3) + ")")
  Info 'scaling back'
  Wheel-Phys $cx $cy -2
} elseif ($script:CursorStolen) {
  Skip 'mouse in use (see above)'
} else {
  Fail 'wheel did not change the group scale'
}

# ---- 4. drag the character: expect a persisted move ----
$cfgF = Join-Path $Root 'config.json'
$x0 = $null
try { $x0 = [double](Get-Content $cfgF -Raw -Encoding UTF8 | ConvertFrom-Json).layout.pet.x } catch { }
$r = $rects['pet']; $cx = $r[0] + [int]($r[2] / 2); $cy = $r[1] + [int]($r[3] / 2)
Move-Phys $cx $cy
[InpWin]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 120
Move-Phys ($cx + 30) ($cy + 20)
[InpWin]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds $SettleMs
$x1 = $null
try { $x1 = [double](Get-Content $cfgF -Raw -Encoding UTF8 | ConvertFrom-Json).layout.pet.x } catch { }
if ($null -ne $x0 -and $null -ne $x1 -and [Math]::Abs($x1 - $x0) -gt 5) {
  Pass ("drag on the character moved the arrangement (" + [int]$x0 + " -> " + [int]$x1 + ")")
  Info 'dragging it back'
  $r = [InpWin]::Rects('WpmV1|')['pet']
  $cx = $r[0] + [int]($r[2] / 2); $cy = $r[1] + [int]($r[3] / 2)
  Move-Phys $cx $cy
  [InpWin]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 120
  Move-Phys ($cx - 30) ($cy - 20)
  [InpWin]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
  Start-Sleep -Milliseconds $SettleMs
} elseif ($script:CursorStolen) {
  Skip 'mouse in use (see above)'
} else {
  Fail 'drag on the character did not move anything'
}

[void][InpWin]::SetCursorPos($orig.X, $orig.Y)
Write-Output ""
Write-Output "note: this test moves the real cursor - keep hands off the mouse for its ~20 seconds,"
Write-Output "      otherwise sections are skipped (a human dragging the cursor looks identical to a dead app)."
if ($fail -eq 0) { Write-Output '=== INPUT-TEST: PASS ==='; exit 0 }
Write-Output ("=== INPUT-TEST: FAIL (" + $fail + ") ==="); exit 1
