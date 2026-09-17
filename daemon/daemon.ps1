param()
$ErrorActionPreference = 'Continue'
# project root = the parent of this daemon folder (relocatable)
$Root  = Split-Path -Parent $PSScriptRoot
$Tools = Join-Path $Root 'tools'
$Run   = Join-Path $Root 'runtime'
$Log   = Join-Path $Run 'daemon.log'

function Log($msg) {
  $line = ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg)
  Add-Content -Path $Log -Value $line -Encoding UTF8
}

# read one-shot command from runtime\command.txt (default: daemon)
$Mode = 'daemon'
$cmdFile = Join-Path $Run 'command.txt'
if (Test-Path $cmdFile) {
  $Mode = (Get-Content $cmdFile -Raw).Trim()
  Remove-Item $cmdFile -Force
}
Log ("=== daemon invoked, mode={0} ===" -f $Mode)

if ($Mode -eq 'install-rtss') {
  $zip = Get-ChildItem (Join-Path $Tools '*.zip') | Select-Object -First 1
  if (-not $zip) { Log 'rtss zip not found'; exit 1 }
  $ex = Join-Path $Tools 'rtss_extract'
  if (Test-Path $ex) { Remove-Item $ex -Recurse -Force }
  Expand-Archive -Path $zip.FullName -DestinationPath $ex -Force
  $setup = Get-ChildItem (Join-Path $ex '*.exe') | Select-Object -First 1
  if (-not $setup) { Log 'setup exe not found'; exit 1 }
  Log ("installing: " + $setup.FullName)
  $p = Start-Process -FilePath $setup.FullName -ArgumentList '/S' -Wait -PassThru
  Log ("installer exit code: " + $p.ExitCode)
  $rtss = Join-Path ${env:ProgramFiles(x86)} 'RivaTuner Statistics Server\RTSS.exe'
  if (Test-Path $rtss) {
    Log 'RTSS installed, starting'
    Start-Process -FilePath $rtss
    Start-Sleep -Seconds 3
  } else {
    Log 'RTSS.exe NOT found after install'
  }
  Get-Process RTSS -ErrorAction SilentlyContinue | ForEach-Object { Log ("RTSS running pid=" + $_.Id) }
  exit 0
}

if ($Mode -eq 'probe-rtss') {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class RtssProbe {
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern IntPtr OpenFileMapping(uint dwDesiredAccess, bool bInheritHandle, string lpName);
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern IntPtr MapViewOfFile(IntPtr hFileMappingObject, uint dwDesiredAccess, uint dwFileOffsetHigh, uint dwFileOffsetLow, uint dwNumberOfBytesToMap);
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern bool UnmapViewOfFile(IntPtr lpBaseAddress);
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern bool CloseHandle(IntPtr hObject);

  public static string Probe() {
    IntPtr h = OpenFileMapping(0x0004, false, "RTSS_SHARED_MEMORY");
    if (h == IntPtr.Zero) return "MAPPING-NOT-FOUND err=" + Marshal.GetLastWin32Error();
    IntPtr p = MapViewOfFile(h, 0x0004, 0, 0, 4096);
    if (p == IntPtr.Zero) { CloseHandle(h); return "MAP-FAILED"; }
    int sig = Marshal.ReadInt32(p, 0);
    int ver = Marshal.ReadInt32(p, 4);
    int off = Marshal.ReadInt32(p, 8);
    int ent = Marshal.ReadInt32(p, 12);
    int cnt = Marshal.ReadInt32(p, 16);
    string s = string.Format("sig=0x{0:X} ver=0x{1:X} entryOff={2} entrySize={3} entries={4}", sig, ver, off, ent, cnt);
    UnmapViewOfFile(p);
    CloseHandle(h);
    return s;
  }
}
'@
  Log ("RTSS shm probe: " + [RtssProbe]::Probe())
  exit 0
}

if ($Mode -eq 'start-rtss') {
  $rtss = Join-Path ${env:ProgramFiles(x86)} 'RivaTuner Statistics Server\RTSS.exe'
  if (Test-Path $rtss) {
    Start-Process -FilePath $rtss
    Log 'RTSS started via daemon'
  } else { Log 'rtss exe missing' }
  exit 0
}

if ($Mode -eq 'cleanup-leftovers') {
  # v4-era hazard: a probe launched PresentMon elevated and it kept running for
  # hours (a leftover that outlives the pet, so quitting the pet never removed
  # it).  This mode exists so the *elevated* task can reap such leftovers.
  $killed = 0
  foreach ($n in 'PresentMon_x64', 'PresentMon', 'PresentMon1') {
    Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object {
      Log ("killing leftover " + $_.ProcessName + " pid=" + $_.Id + " started=" + $_.StartTime)
      try { Stop-Process -Id $_.Id -Force -ErrorAction Stop; $killed++ } catch { Log ("  failed: " + $_.Exception.Message) }
    }
  }
  Log ("cleanup-leftovers done, killed=" + $killed)
  exit 0
}

if ($Mode -eq 'selftest') {
  Log 'selftest removed (presentmon verdict: unsupported on this OS build)'
  exit 0
}

Log 'daemon mode placeholder (pet will replace this)'
exit 0
