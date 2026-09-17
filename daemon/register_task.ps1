$vbs   = Join-Path $PSScriptRoot 'launcher.vbs'
$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('"' + $vbs + '"')
$user = "$env:USERDOMAIN\$env:USERNAME"
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
# migrate away from the pre-release task name if it exists
Unregister-ScheduledTask -TaskName 'WhaleMonFPS' -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName 'ZZZSunnaMonitor_RTSS' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Host 'REGISTER-OK (task: ZZZSunnaMonitor_RTSS)'
