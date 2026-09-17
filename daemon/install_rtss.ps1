# install_rtss.ps1 - one-click RTSS installer for ZZZ Sunna PerfMonitor (ASCII only)
# Runs the BUNDLED OFFICIAL RTSS installer silently (no settings changed, /S),
# then starts RTSS. The package under Redist\ is the unmodified official
# distribution (c) Unwinder / Guru3D - see the included provenance file.
# Usage: run via install_rtss.vbs (double-click) or:
#   powershell -NoProfile -ExecutionPolicy Bypass -File daemon\install_rtss.ps1
$ErrorActionPreference = 'Stop'
$root    = Split-Path -Parent $PSScriptRoot
$rtssExe = Join-Path ${env:ProgramFiles(x86)} 'RivaTuner Statistics Server\RTSS.exe'

if (Test-Path $rtssExe) {
  Write-Host ''
  Write-Host '[OK] RTSS is already installed on this computer.'
  if (-not (Get-Process RTSS -ErrorAction SilentlyContinue)) {
    try { Start-Process -FilePath $rtssExe; Write-Host '[OK] RTSS started.' } catch { }
  }
  Write-Host '[OK] Nothing else to do - game FPS will show on the pet panel.'
  exit 0
}

$zip = $null
foreach ($dir in @((Join-Path $root 'Redist'), (Join-Path $root 'tools'))) {
  if (Test-Path $dir) {
    $zip = Get-ChildItem -Path $dir -Filter '*.zip' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($zip) { break }
  }
}
if (-not $zip) {
  Write-Host ''
  Write-Host '[ERROR] Bundled RTSS package not found (Redist\*.zip missing).'
  Write-Host 'Manual install: https://www.guru3d.com/download/rtss-rivatuner-statistics-server-download/'
  exit 1
}

$tmp = Join-Path $env:TEMP ('rtss_install_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
Expand-Archive -Path $zip.FullName -DestinationPath $tmp -Force
$setup = Get-ChildItem -Path $tmp -Recurse -Filter 'RTSSSetup*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $setup) {
  Write-Host '[ERROR] Installer not found inside the bundled package.'
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  exit 1
}

Write-Host ''
Write-Host 'Installing RTSS silently... please click YES on the Windows UAC prompt.'
try {
  $p = Start-Process -FilePath $setup.FullName -ArgumentList '/S' -Wait -PassThru
} catch {
  Write-Host '[ERROR] Install was cancelled (UAC prompt declined?). Run again and click YES.'
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  exit 1
}
Start-Sleep -Seconds 3
if (Test-Path $rtssExe) {
  try { Start-Process -FilePath $rtssExe } catch { }
  Write-Host ''
  Write-Host '[OK] RTSS installed and started.'
  Write-Host '[OK] It will start with Windows from now on - no settings needed.'
  Write-Host '[OK] Tip: restart the PC once, then start a game - the pet panel'
  Write-Host '     will show the real in-game FPS.'
} else {
  Write-Host '[WARN] Installer finished but RTSS.exe was not found.'
  Write-Host 'Please install manually: https://www.guru3d.com/download/rtss-rivatuner-statistics-server-download/'
}
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
