param([int]$Page=0)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$exe=Join-Path $root 'build\Release\FlowCat.exe'
$name='FlowCat-Preview-Verify'
$action=New-ScheduledTaskAction -Execute $exe -Argument "--show --page $Page"
$principal=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Highest
$settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -Settings $settings -Force | Out-Null
try { Start-ScheduledTask -TaskName $name; Start-Sleep 4; Get-Process FlowCat | Select-Object Id,SessionId,WorkingSet64,PrivateMemorySize64,CPU } finally {Unregister-ScheduledTask -TaskName $name -Confirm:$false}
