#requires -Version 5.1
# 5.13: "Report a problem" (About page and tray menu).
# Opens GitHub's bug-report form in the browser with the details filled in: YUMRAM version, administrator
# mode, Windows version, CPU, RAM and the last lines of YUMRAM.log. Nothing is sent by YUMRAM itself: the
# person sees everything on the GitHub page, can edit or delete it, and only their own "Create" click posts
# it (a GitHub account is needed). Your user name, PC name and user-folder path are replaced in the log.
# Issues opened this way start with "[From app]" so they are easy to find and triage.

function Protect-YumReportText {
    param([string]$Text)
    if([string]::IsNullOrEmpty($Text)){return ''}
    $t=$Text
    foreach($pair in @(@($env:USERPROFILE,'%USERPROFILE%'),@($env:LOCALAPPDATA,'%LOCALAPPDATA%'),@($env:APPDATA,'%APPDATA%'))){
        if(-not [string]::IsNullOrWhiteSpace($pair[0])){ $t=[regex]::Replace($t,[regex]::Escape([string]$pair[0]),[string]$pair[1].Replace('$','$$'),'IgnoreCase') }
    }
    foreach($pair in @(@($env:USERNAME,'<user>'),@($env:COMPUTERNAME,'<pc>'),@($env:USERDOMAIN,'<domain>'))){
        if(-not [string]::IsNullOrWhiteSpace($pair[0]) -and ([string]$pair[0]).Length -ge 3){ $t=[regex]::Replace($t,('\b'+[regex]::Escape([string]$pair[0])+'\b'),[string]$pair[1],'IgnoreCase') }
    }
    # E-mail addresses that a program name or path might contain.
    $t=[regex]::Replace($t,'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}','<email>')
    return $t
}

function Get-YumReportDetails {
    param([int]$LogLines=30)
    $version='';try{$version=[string]$script:Yum.Config.Version}catch{}
    $mode='Not sure'
    try{ switch(Get-YumElevationMode){ 'Ask'{$mode='Ask each time'} 'NoPrompt'{$mode='Start without asking'} 'Never'{$mode='Never'} } }catch{}
    $os='Windows';$cpu='';$ram=''
    try{ $o=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop; $os=('{0} {1} (build {2})' -f $o.Caption,$o.OSArchitecture,$o.BuildNumber).Trim(); $ram=('{0:N1} GB RAM' -f ([double]$o.TotalVisibleMemorySize/1MB)) }catch{}
    try{ $c=@(Get-CimInstance Win32_Processor -ErrorAction Stop)[0]; $cpu=('{0} ({1} cores / {2} threads)' -f ([string]$c.Name).Trim(),$c.NumberOfCores,$c.NumberOfLogicalProcessors) }catch{}
    $admin='';try{$admin=$(if(Test-YumIsElevated){'running as administrator'}else{'running without administrator'})}catch{}
    $battery='';try{ if(@(Get-CimInstance Win32_Battery -ErrorAction Stop).Count){$battery='laptop (has a battery)'}else{$battery='desktop (no battery)'} }catch{}
    $pc=(@($os,$cpu,$ram,$battery,$admin) | Where-Object {$_}) -join "`n"
    $log=''
    try{ $p=[string](Get-YumLogPath); if(Test-Path -LiteralPath $p){ $log=(@(Get-Content -LiteralPath $p -Tail $LogLines -ErrorAction Stop) -join "`n") } }catch{}
    return [pscustomobject]@{Version=$version;Admin=$mode;Pc=(Protect-YumReportText $pc);Log=(Protect-YumReportText $log)}
}

function Get-YumReportUrl {
    # Builds the pre-filled issue URL. GitHub accepts about 8 KB of URL, so the log is shortened from the top.
    param([string]$What='',[switch]$NoLog,$Details)
    if($null -eq $Details){$Details=Get-YumReportDetails}
    $repo='bigmanjer/YumRam';try{if($script:Yum.Config['UpdateRepository']){$repo=[string]$script:Yum.Config['UpdateRepository']}}catch{}
    $title='[From app] '
    $build={ param([string]$LogText)
        $q=[ordered]@{template='bug_report.yml';title=$title;version=[string]$Details.Version;admin=[string]$Details.Admin;pc=[string]$Details.Pc}
        if($What){$q.what=$What}
        if($LogText){$q.log=$LogText}
        $pairs=foreach($k in $q.Keys){ '{0}={1}' -f $k,[uri]::EscapeDataString([string]$q[$k]) }
        'https://github.com/{0}/issues/new?{1}' -f $repo,($pairs -join '&')
    }
    $log=$(if($NoLog){''}else{[string]$Details.Log})
    if($log.Length -gt 5000){$log=$log.Substring($log.Length-5000);$nl=$log.IndexOf("`n");if($nl -ge 0){$log=$log.Substring($nl+1)}}   # keep the newest lines
    $url=& $build $log
    while($url.Length -gt 7500 -and $log.Length -gt 0){
        $lines=@($log -split "`n"); if($lines.Count -le 1){$log='';}else{$log=($lines[[int][math]::Ceiling($lines.Count/4)..($lines.Count-1)] -join "`n")}
        $url=& $build $log
    }
    return $url
}

function Open-YumReportProblem {
    try{
        $url=Get-YumReportUrl
        Start-Process $url
        try{Write-YumLog 'Report a problem: opened the GitHub bug-report form in the browser (nothing is sent until you press Create).'}catch{}
        return $true
    }catch{
        try{Write-YumLogException -Context 'Report a problem failed' -Exception $_.Exception}catch{}
        try{Start-Process 'https://github.com/bigmanjer/YumRam/issues/new/choose'}catch{}
        return $false
    }
}
