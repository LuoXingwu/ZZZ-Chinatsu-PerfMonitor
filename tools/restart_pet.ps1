# 重启桌宠：杀掉现有 pet.ps1 实例 → 重新拉起（走 C:\wpm ASCII 联接点）
$old = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*pet.ps1*' -and $_.ProcessId -ne $PID }
foreach ($p in $old) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 1
Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\wpm\pet.ps1' -WindowStyle Hidden
Start-Sleep -Seconds 6
$new = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*pet.ps1*' -and $_.ProcessId -ne $PID }
foreach ($p in $new) {
  $proc = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
  if ($proc) { Write-Output ("pet pid={0} WS={1:N0}MB" -f $p.ProcessId, ($proc.WorkingSet64 / 1MB)) }
}
