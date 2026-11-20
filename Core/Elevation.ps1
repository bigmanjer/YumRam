#requires -Version 5.1
# 5.12: administrator without a prompt every time.
#
# ElevationMode (Settings > General):
#   Ask      - default: Windows asks (UAC) each time YUMRAM starts without administrator.
#   NoPrompt - one-time setup creates a scheduled task "YUMRAM" that runs YUMRAM with highest privileges;
#              YUMRAM.exe / the scripts then start through it, so there is no prompt (the method Windows
#              power-user tools use). Optional: also start it when you sign in.
#   Never    - never ask; YUMRAM runs without the admin-only reclaim steps.
# Trade-off (said in Settings): with NoPrompt, any program running as you could change YUMRAM's files and
# get administrator through that task. Microsoft does not treat UAC as a security boundary for the same
# user, but it is still a choice the user makes, so it is opt-in.

$script:YumElevatedTaskName='YUMRAM'

function Get-YumElevationMode {
    $m='Ask';try{if($script:Yum.Config.Contains('ElevationMode') -and $script:Yum.Config['ElevationMode']){$m=[string]$script:Yum.Config['ElevationMode']}}catch{}
    if($m -notin @('Ask','NoPrompt','Never')){$m='Ask'}
    return $m
}

function Get-YumElevatedTask {
    try{ return Get-ScheduledTask -TaskName $script:YumElevatedTaskName -TaskPath '\' -ErrorAction Stop }catch{ return $null }
}

function Test-YumElevatedTaskCurrent {
    # The task must point at THIS YUMRAM folder (it moves if the folder is moved or renamed).
    $t=Get-YumElevatedTask;if($null -eq $t){return $false}
    try{ $taskArgs=[string]$t.Actions[0].Arguments; return ($taskArgs -like ('*{0}*' -f (Join-Path $script:Yum.Root 'App\YUMRAM.ps1'))) }catch{ return $false }
}

function Install-YumElevatedTask {
    # Needs administrator (creating a highest-privilege task). Returns @{Success;Message}.
    param([switch]$AtLogon)
    if(-not (Test-YumIsElevated)){return [pscustomobject]@{Success=$false;Message='Run YUMRAM as administrator once to set this up.'}}
    try{
        $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $script=Join-Path $script:Yum.Root 'App\YUMRAM.ps1'
        $action=New-ScheduledTaskAction -Execute $ps -Argument ('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $script) -WorkingDirectory ([string]$script:Yum.Root)
        $user=[Security.Principal.WindowsIdentity]::GetCurrent().Name
        $principal=New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
        $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -StartWhenAvailable
        $triggers=@();if($AtLogon){$tr=New-ScheduledTaskTrigger -AtLogOn -User $user;$tr.Delay='PT20S';$triggers+=$tr}
        $params=@{TaskName=$script:YumElevatedTaskName;TaskPath='\';Action=$action;Principal=$principal;Settings=$settings;Description='Starts YUMRAM with administrator rights without a UAC prompt (set up in YUMRAM Settings). Delete this task to go back to prompting.';Force=$true}
        if($triggers.Count){$params.Trigger=$triggers}
        Register-ScheduledTask @params | Out-Null
        try{Write-YumLog ('No-prompt start set up: scheduled task "{0}" (highest privileges{1}).' -f $script:YumElevatedTaskName,$(if($AtLogon){', also at sign-in'}else{''}))}catch{}
        return [pscustomobject]@{Success=$true;Message=$(if($AtLogon){'Set up: YUMRAM starts as administrator without asking, also when you sign in.'}else{'Set up: YUMRAM starts as administrator without asking.'})}
    }catch{ return [pscustomobject]@{Success=$false;Message=('Windows refused to create the task: {0}' -f $_.Exception.Message)} }
}

function Remove-YumElevatedTask {
    try{ if($null -ne (Get-YumElevatedTask)){ Unregister-ScheduledTask -TaskName $script:YumElevatedTaskName -TaskPath '\' -Confirm:$false -ErrorAction Stop; try{Write-YumLog 'No-prompt start removed (scheduled task deleted).'}catch{} }; return $true }catch{ return $false }
}

function Get-YumElevationHint {
    param([string]$Mode)
    $admin=Test-YumIsElevated
    switch($Mode){
        'NoPrompt'{ if(Test-YumElevatedTaskCurrent){'Set up: YUMRAM starts as administrator without asking. Trade-off: any program running as you could change YUMRAM''s files and get administrator through this. Choose "Ask each time" to remove it.'}elseif($admin){'Press Apply to set it up (one time). Trade-off: any program running as you could then change YUMRAM''s files and get administrator through it.'}else{'Needs YUMRAM to be running as administrator once to set up.'} }
        'Never'{ 'YUMRAM never asks. Free RAM now and automatic care still trim programs; the file cache, memory lists, memory combining and "all users" startup apps are skipped.' }
        default{ $(if($admin){'Windows asks each time YUMRAM starts (running as administrator now).'}else{'Windows asks each time YUMRAM starts (not running as administrator now).'}) }
    }
}

function Set-YumElevationChoice {
    # Applies Settings > General > Administrator rights + Start with Windows. Returns @{Success;Message}.
    param([ValidateSet('Ask','NoPrompt','Never')][string]$Mode,[bool]$StartWithWindows)
    $runKey='Software\Microsoft\Windows\CurrentVersion\Run'
    $exe=Join-Path ([string]$script:Yum.Root) 'YUMRAM.exe'
    $setRun={param([bool]$On) $k=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($runKey); try{ if($On -and (Test-Path -LiteralPath $exe)){$k.SetValue('YUMRAM',('"{0}"' -f $exe))}else{$k.DeleteValue('YUMRAM',$false)} }finally{$k.Close()} }
    if($Mode -eq 'NoPrompt'){
        $r=Install-YumElevatedTask -AtLogon:$StartWithWindows
        if(-not $r.Success){return $r}
        & $setRun $false   # the task's sign-in trigger replaces the Run entry
    } else {
        if($null -ne (Get-YumElevatedTask) -and -not (Test-YumIsElevated)){return [pscustomobject]@{Success=$false;Message='Removing the no-prompt task needs YUMRAM to run as administrator.'}}
        [void](Remove-YumElevatedTask)
        try{ & $setRun $StartWithWindows }catch{}
    }
    Update-YumConfigValue -Name ElevationMode -Value $Mode
    Update-YumConfigValue -Name StartWithWindows -Value $StartWithWindows
    return [pscustomobject]@{Success=$true;Message=(Get-YumElevationHint -Mode $Mode)}
}

function Start-YumViaElevatedTask {
    # Starting an existing task needs no elevation; the task itself runs with highest privileges.
    try{ if(-not (Test-YumElevatedTaskCurrent)){return $false}; Start-ScheduledTask -TaskName $script:YumElevatedTaskName -TaskPath '\' -ErrorAction Stop; return $true }catch{ return $false }
}
