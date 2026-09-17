# rtss_dump.ps1 - dump every RTSS shared memory app entry (ASCII only).
# Offsets verified against the vendor SDK header RTSSSharedMemory.h:
#   header: +0 signature, +4 version, +8 appEntrySize, +12 appArrOffset,
#           +16 appArrSize, +68 lastForegroundAppProcessID
#   entry : +0 pid, +4 char szName[260], +268 time0, +272 time1, +276 frames
# fps = 1000 * frames / (time1 - time0)
# Use this to verify the game path: run a game, then run this script and check
# that the game process appears with a plausible fps and is the foreground pid.
$ErrorActionPreference = 'Continue'
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class RtssDump {
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  static extern IntPtr OpenFileMapping(uint acc, bool inh, string name);
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern IntPtr MapViewOfFile(IntPtr h, uint acc, uint hi, uint lo, uint size);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool UnmapViewOfFile(IntPtr p);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  public static List<string> Dump() {
    List<string> o = new List<string>();
    IntPtr h = OpenFileMapping(0x0004, false, "RTSSSharedMemoryV2");
    if (h == IntPtr.Zero) { o.Add("RTSS shared memory not found - is RTSS running?"); return o; }
    IntPtr p = MapViewOfFile(h, 0x0004, 0, 0, 0);
    if (p == IntPtr.Zero) { CloseHandle(h); o.Add("MapViewOfFile failed"); return o; }
    try {
      int sig = Marshal.ReadInt32(p, 0);
      if (sig != 0x52545353) { o.Add("bad signature 0x" + sig.ToString("X")); return o; }
      int ver = Marshal.ReadInt32(p, 4);
      int esz = Marshal.ReadInt32(p, 8);
      int aoff = Marshal.ReadInt32(p, 12);
      int acnt = Marshal.ReadInt32(p, 16);
      int fg = Marshal.ReadInt32(p, 68);
      o.Add(string.Format("header: version=0x{0:X} ({1}.{2}) entrySize={3} arrOffset={4} arrCount={5} foregroundPid={6}",
        ver, (ver >> 16), (ver & 0xFFFF), esz, aoff, acnt, fg));
      int n = 0;
      for (int i = 0; i < acnt && i < 256; i++) {
        IntPtr e = (IntPtr)((long)p + aoff + (long)i * esz);
        int pid = Marshal.ReadInt32(e, 0);
        if (pid <= 0) continue;
        int t0 = Marshal.ReadInt32(e, 268);
        int t1 = Marshal.ReadInt32(e, 272);
        int fr = Marshal.ReadInt32(e, 276);
        StringBuilder nm = new StringBuilder(64);
        for (int c = 0; c < 259; c++) {
          byte b = Marshal.ReadByte(e, 4 + c);
          if (b == 0) break;
          if (b >= 0x20 && b < 0x7F) nm.Append((char)b);
        }
        double fps = (t1 > t0) ? (1000.0 * fr / (t1 - t0)) : -1;
        o.Add(string.Format("slot={0,-4} pid={1,-7} fps={2,7:F1} frames={3,-7} dt={4,-7} {5}{6}",
          i, pid, fps, fr, t1 - t0, nm.ToString(), (pid == fg ? "   <== FOREGROUND" : "")));
        n++;
      }
      if (n == 0) o.Add("(no active app entries - RTSS has not hooked anything yet)");
    } catch (Exception ex) { o.Add("error: " + ex.Message); }
    finally { UnmapViewOfFile(p); CloseHandle(h); }
    return o;
  }
}
'@
Write-Output "=== RTSS shared memory ==="
[RtssDump]::Dump() | ForEach-Object { Write-Output $_ }
