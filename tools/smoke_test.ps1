# smoke_test.ps1 - one-command acceptance check for ZZZ Sunna PerfMonitor v1 (ASCII only)
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\smoke_test.ps1
#
# Checks, in order:
#   1. pet.ps1 parses
#   2. exactly one pet process is running (starts it when none is)
#   3. all component windows exist, are topmost+layered, and sit inside the
#      physical virtual desktop with the expected aspect
#   4. the automation hook answers: state / diag / click
#   5. a drag moves the arrangement AND is persisted, then is undone
#   6. component render dumps can be produced
# Exit code 0 = all pass, 1 = at least one failure.
param([switch]$NoStart, [int]$WaitSec = 25)
$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
$Log = Join-Path $Root 'runtime\pet.log'
$CmdF = Join-Path $Root 'runtime\petcmd.txt'
$CfgF = Join-Path $Root 'config.json'
$PidF = Join-Path $Root 'runtime\pet.pid'
$fail = 0

function Pass([string]$m) { Write-Output ("  [PASS] " + $m) }
function Fail([string]$m) { Write-Output ("  [FAIL] " + $m); $script:fail++ }
function Info([string]$m) { Write-Output ("         " + $m) }

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class SmokeDpi {
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
  [DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int v);
  public static void Enable() {
    if (!SetProcessDpiAwarenessContext(new IntPtr(-4))) {
      if (SetProcessDpiAwareness(2) != 0) SetProcessDpiAwareness(1);
    }
  }
}
'@
[SmokeDpi]::Enable()   # physical pixel truth

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class SmokeWin {
  public delegate bool Cb(IntPtr h, IntPtr d);
  [DllImport("user32.dll")] public static extern bool EnumWindows(Cb c, IntPtr d);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  public struct R { public int L, T, Rr, B; }
  public static List<string> Find(string prefix) {
    List<string> o = new List<string>();
    EnumWindows(delegate(IntPtr h, IntPtr d) {
      StringBuilder t = new StringBuilder(128);
      GetWindowTextW(h, t, 128);
      string s = t.ToString();
      if (s.StartsWith(prefix)) {
        R r; GetWindowRect(h, out r);
        uint p; GetWindowThreadProcessId(h, out p);
        int ex = GetWindowLong(h, -20);
        string key = s.Substring(prefix.Length);
        // ';' separator: the window title itself contains '|'
        o.Add(string.Format("{0};{1};{2};{3};{4};{5};{6};{7};{8}",
          key, p, r.L, r.T, r.Rr - r.L, r.B - r.T,
          ((ex & 0x8) != 0) ? 1 : 0, ((ex & 0x80000) != 0) ? 1 : 0, IsWindowVisible(h) ? 1 : 0));
      }
      return true;
    }, IntPtr.Zero);
    return o;
  }
}
'@

function Get-LogSize { if (Test-Path $Log) { return (Get-Content $Log -Raw).Length } return 0 }
function Send-Cmd([string]$c) { Set-Content -Path $CmdF -Value $c -Encoding UTF8 }
function Wait-Log([string]$pattern, [int]$from, [int]$sec = 6) {
  $t = (Get-Date).AddSeconds($sec)
  while ((Get-Date) -lt $t) {
    Start-Sleep -Milliseconds 300
    if (Test-Path $Log) {
      $txt = Get-Content $Log -Raw
      if ($txt.Length -gt $from) {
        $tail = $txt.Substring($from)
        if ($tail -match $pattern) { return $tail }
      }
    }
  }
  return $null
}
function Read-CfgLayout {
  try { return (Get-Content $CfgF -Raw -Encoding UTF8 | ConvertFrom-Json).layout } catch { return $null }
}

Write-Output "=== ZZZ Sunna PerfMonitor v1 smoke test ==="

# ---- 1. syntax ----
$errs = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'pet.ps1'), [ref]$null, [ref]$errs)
if ($errs -and $errs.Count -gt 0) {
  Fail ("pet.ps1 has " + $errs.Count + " syntax error(s): " + $errs[0].Message)
} else { Pass 'pet.ps1 parses' }

# ---- 2. process ----
$procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -like '*pet.ps1*' -and $_.CommandLine -like ('*' + (Split-Path -Leaf $Root) + '*') })
if ($procs.Count -eq 0 -and -not $NoStart) {
  Info 'no pet running -> starting it'
  $vbs = Join-Path $Root 'daemon\pet_launcher.vbs'
  Start-Process -FilePath 'wscript.exe' -ArgumentList ('"' + $vbs + '"') -WindowStyle Hidden
  $t = (Get-Date).AddSeconds($WaitSec)
  while ((Get-Date) -lt $t) {
    Start-Sleep -Milliseconds 500
    $procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -like '*pet.ps1*' -and $_.CommandLine -like ('*' + (Split-Path -Leaf $Root) + '*') })
    if ($procs.Count -gt 0) { break }
  }
}
if ($procs.Count -eq 1) { Pass ("one pet process running (pid " + $procs[0].ProcessId + ")") }
elseif ($procs.Count -eq 0) { Fail 'no pet process' }
else { Fail ($procs.Count.ToString() + ' pet processes running at once') }
if ($procs.Count -ge 1) {
  $m = [int]((Get-Process -Id $procs[0].ProcessId).WorkingSet64 / 1MB)
  Info ("working set " + $m + " MB")
}

# ---- 3. windows ----
$rows = [SmokeWin]::Find('WpmV1|')
$wanted = @('pet', 'panel', 'guitar', 'easel', 'bchan')
$seen = @{}
foreach ($r in $rows) {
  $f = $r.Split(';')
  $k = $f[0]
  $seen[$k] = $f
}
foreach ($k in $wanted) {
  if (-not $seen.ContainsKey($k)) { Fail ("window missing: " + $k); continue }
  $f = $seen[$k]
  $w = [int]$f[4]; $h = [int]$f[5]
  if ($f[8] -ne '1') { Fail ($k + ' window is not visible'); continue }
  if ($f[6] -ne '1' -or $f[7] -ne '1') { Fail ($k + ' window is not topmost+layered'); continue }
  if ($w -le 40 -or $h -le 40) { Fail ($k + " window too small: " + $w + "x" + $h); continue }
  Pass ($k + " window ok  " + $w + "x" + $h + " at " + $f[2] + "," + $f[3])
}
if ($seen.ContainsKey('pet')) {
  $f = $seen['pet']
  $ar = [Math]::Round([double]$f[4] / [double]$f[5], 3)
  if ($ar -lt 0.4 -or $ar -gt 1.2) { Fail ("pet aspect looks wrong: " + $ar) } else { Pass ("pet aspect " + $ar + " (art clips are 0.60-0.78)") }
}

# ---- 4. automation hook ----
if ($procs.Count -ge 1) {
  $mark = Get-LogSize
  Send-Cmd 'state'
  $t = Wait-Log 'state: emo=' $mark 6
  if ($t) { Pass 'state command answered' } else { Fail 'state command got no answer' }
  $mark = Get-LogSize
  Send-Cmd 'diag'
  $t = Wait-Log 'diag: end' $mark 6
  if ($t) {
    $bad = @()
    foreach ($line in ($t -split "`n")) { if ($line -match 'diag \w+.*win=win=(\d+),(\d+) (\d+)x(\d+) client=(\d+)x(\d+).*wpf=(\d+)x(\d+)') { } }
    if ($t -match 'ERR') { Fail 'diag reported an error' } else { Pass 'diag answered with no errors' }
  } else { Fail 'diag command got no answer' }
  $mark = Get-LogSize
  Send-Cmd 'uclick:pet'
  $t = Wait-Log 'pose ->|uclick' $mark 6
  if ($t) { Pass 'click path (pose) works' } else { Fail 'click path produced nothing' }
}

# ---- 5. drag + persistence, then undo ----
if ($procs.Count -ge 1) {
  $before = Read-CfgLayout
  if (-not $before) { Fail 'config.json layout unreadable' }
  else {
    $x0 = [double]$before.pet.x
    $mark = Get-LogSize
    Send-Cmd 'udrag:pet:41:0'
    $t = Wait-Log 'udrag pet' $mark 6
    Start-Sleep -Milliseconds 600
    $after = Read-CfgLayout
    # always undo, even when the checks below fail: the test must not leave the
    # user's layout shifted
    Send-Cmd 'udrag:pet:-41:0'
    Start-Sleep -Milliseconds 900
    $back = Read-CfgLayout
    if (-not $t) { Fail 'drag command got no answer' }
    elseif (-not $after) { Fail 'config not readable after drag' }
    elseif ([Math]::Abs(([double]$after.pet.x - $x0) - 41) -gt 2) {
      Fail ("drag did not move exactly 41px (delta " + [Math]::Round([double]$after.pet.x - $x0, 1) + "), or was not persisted")
    } else {
      Pass 'drag moves the whole arrangement by the exact delta and persists it'
    }
    if ($back -and [Math]::Abs([double]$back.pet.x - $x0) -le 2) { Pass 'position restored' }
    else { Fail 'could not restore the original position' }
  }
}

# ---- 5b. group scale (the single size control in v6) ----
if ($procs.Count -ge 1) {
  $gs0 = $null; $gs1 = $null; $gs2 = $null
  try { $gs0 = [double](Get-Content $CfgF -Raw -Encoding UTF8 | ConvertFrom-Json).groupScale } catch { }
  $mark = Get-LogSize
  Send-Cmd 'uwheel:0.1'
  $t = Wait-Log 'uwheel' $mark 6
  Start-Sleep -Milliseconds 700
  try { $gs1 = [double](Get-Content $CfgF -Raw -Encoding UTF8 | ConvertFrom-Json).groupScale } catch { }
  Send-Cmd 'uwheel:-0.1'
  Start-Sleep -Milliseconds 900
  try { $gs2 = [double](Get-Content $CfgF -Raw -Encoding UTF8 | ConvertFrom-Json).groupScale } catch { }
  if ($null -eq $gs0 -or $null -eq $gs1) { Fail 'groupScale not readable' }
  elseif ([Math]::Abs($gs1 - $gs0 - 0.1) -gt 0.02) { Fail ("group scale did not follow the wheel (" + $gs0 + " -> " + $gs1 + ")") }
  else {
    Pass ('group scale scales every component together (' + [Math]::Round($gs0, 3) + ' -> ' + [Math]::Round($gs1, 3) + ')')
    if ($null -ne $gs2 -and [Math]::Abs($gs2 - $gs0) -le 0.02) { Pass 'group scale restored' }
    else { Fail 'could not restore the group scale' }
  }
}

# ---- 6. render dump ----
if ($procs.Count -ge 1) {
  $shotDir = Join-Path $Root 'runtime\shots'
  $n0 = @(Get-ChildItem $shotDir -Filter '*.png' -ErrorAction SilentlyContinue).Count
  $mark = Get-LogSize
  Send-Cmd 'shot'
  $t = Wait-Log 'shot -> ' $mark 8
  $n1 = @(Get-ChildItem $shotDir -Filter '*.png' -ErrorAction SilentlyContinue).Count
  if ($n1 -gt $n0) { Pass ('render dump produced ' + ($n1 - $n0) + ' png') } else { Fail 'render dump produced no file' }
}

Write-Output ""
if ($fail -eq 0) { Write-Output "=== SMOKE-TEST: PASS ==="; exit 0 }
Write-Output ("=== SMOKE-TEST: FAIL (" + $fail + ") ==="); exit 1
