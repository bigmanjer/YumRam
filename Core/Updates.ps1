#requires -Version 5.1
# 5.10: updates from GitHub Releases.
#
# Check:   GET https://api.github.com/repos/<UpdateRepository>/releases/latest at most once a day (opt-out
#          in Settings). Only a generic User-Agent is sent; nothing about you or your PC.
# Verify:  the release must contain YUMRAM-<version>.zip and its SHA-256 (GitHub's own asset "digest",
#          or a SHA256SUMS.txt asset). No hash = no install. The unpacked VERSION must match the tag.
# Install: download to %TEMP%, verify, unpack to a staging folder, then the new YUMRAM.exe applies it
#          after this YUMRAM closes: backs up program files to .previous, copies the update in (your
#          config, statistics, learned data and logs are never touched) and starts YUMRAM again.
#          Undo: YUMRAM.exe --rollback.

function ConvertTo-YumVersion {
    param([string]$Text)
    $t=([string]$Text).Trim() -replace '^[vV]',''
    $m=[regex]::Match($t,'^\d+(\.\d+){1,3}')
    if(-not $m.Success){return $null}
    try{ return [version]$m.Value }catch{ return $null }
}

function Get-YumUpdateFeedUrl {
    $c=$script:Yum.Config
    $override='';try{$override=[string]$c['UpdateFeedUrl']}catch{}
    if(-not [string]::IsNullOrWhiteSpace($override)){return $override}   # tests / mirrors
    $repo='bigmanjer/YumRam';try{if($c['UpdateRepository']){$repo=[string]$c['UpdateRepository']}}catch{}
    return ('https://api.github.com/repos/{0}/releases/latest' -f $repo)
}

function Invoke-YumUpdateRequest {
    param([string]$Url,[string]$OutFile)
    if($Url -match '^file:'){ $path=([uri]$Url).LocalPath; if($OutFile){Copy-Item -LiteralPath $path -Destination $OutFile -Force;return $null}; return [IO.File]::ReadAllText($path) }
    [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $wc=New-Object System.Net.WebClient
    $wc.Headers['User-Agent']='YUMRAM-Updater'
    $wc.Headers['Accept']='application/vnd.github+json'
    try{ if($OutFile){$wc.DownloadFile($Url,$OutFile);return $null}; return $wc.DownloadString($Url) } finally { $wc.Dispose() }
}

function Get-YumUpdateInfo {
    # Returns @{Status='UpToDate'|'Available'|'NoRelease'|'Error'; Current; Latest; Notes; ZipUrl; Sha256; PageUrl; Message}
    $current=ConvertTo-YumVersion ([string]$script:Yum.Config.Version)
    $info=[ordered]@{Status='Error';Current=[string]$current;Latest='';Notes='';ZipUrl='';ZipName='';Sha256='';PageUrl='';Message='';CheckedAt=(Get-Date)}
    try{
        $json=Invoke-YumUpdateRequest -Url (Get-YumUpdateFeedUrl)
        $rel=$json | ConvertFrom-Json
        $latest=ConvertTo-YumVersion ([string]$rel.tag_name)
        if($null -eq $latest){$info.Message=('The latest release tag "{0}" is not a version number.' -f $rel.tag_name);return [pscustomobject]$info}
        $info.Latest=[string]$latest;$info.Notes=[string]$rel.body;$info.PageUrl=[string]$rel.html_url
        $zip=$null;$sums=$null
        foreach($a in @($rel.assets)){
            $n=[string]$a.name
            if($n -match '(?i)^YUMRAM.*\.zip$'){$zip=$a}
            elseif($n -match '(?i)^SHA256SUMS(\.txt)?$'){$sums=$a}
        }
        if($null -ne $zip){
            $info.ZipUrl=[string]$zip.browser_download_url;$info.ZipName=[string]$zip.name
            # GitHub publishes a "digest" (sha256:...) for every release asset.
            try{ if($zip.PSObject.Properties['digest'] -and [string]$zip.digest -match '^sha256:([0-9a-fA-F]{64})$'){$info.Sha256=$Matches[1].ToUpperInvariant()} }catch{}
            if(-not $info.Sha256 -and $null -ne $sums){
                try{
                    $txt=Invoke-YumUpdateRequest -Url ([string]$sums.browser_download_url)
                    foreach($line in ($txt -split "`r?`n")){ if($line -match ('^([0-9a-fA-F]{64})\s+\*?' + [regex]::Escape($info.ZipName) + '\s*$')){$info.Sha256=$Matches[1].ToUpperInvariant()} }
                }catch{}
            }
        }
        if($latest -le $current){$info.Status='UpToDate';$info.Message=('You have the latest version ({0}).' -f $current)}
        elseif(-not $info.ZipUrl){$info.Status='Error';$info.Message=('Version {0} is out, but it has no YUMRAM zip to install. Download it from the release page.' -f $latest)}
        elseif(-not $info.Sha256){$info.Status='Error';$info.Message=('Version {0} is out, but it has no SHA-256 to verify it, so YUMRAM will not install it automatically.' -f $latest)}
        else{$info.Status='Available';$info.Message=('Version {0} is available (you have {1}).' -f $latest,$current)}
    }catch{
        $msg=$_.Exception.Message
        if($msg -match '404'){$info.Status='NoRelease';$info.Message='No YUMRAM release has been published on GitHub yet.'}
        else{$info.Message=('Could not reach GitHub: {0}' -f $msg)}
    }
    return [pscustomobject]$info
}

function Test-YumUpdateCheckDue {
    try{ if(-not [bool]$script:Yum.Config['UpdateCheckEnabled']){return $false} }catch{return $false}
    $last=[datetime]::MinValue;try{$last=[datetime]::Parse([string]$script:Yum.Config['UpdateLastCheck'],[Globalization.CultureInfo]::InvariantCulture)}catch{}
    # 5.15.3: every 6 hours (was once a day, and only when YUMRAM started - a copy running in the tray for days
    # never looked again). The UI timer asks every 30 minutes; this decides.
    return (((Get-Date)-$last).TotalHours -ge 6)
}

function Invoke-YumApplyStagedUpdate {
    # Hands a downloaded, verified update to the new YUMRAM.exe, which waits for this process to exit, swaps the
    # files (keeping settings and data) and starts YUMRAM again.
    param([Parameter(Mandatory=$true)][string]$Staging,[switch]$NoRestart)
    $exe=Join-Path $Staging 'YUMRAM.exe'
    if(-not (Test-Path -LiteralPath $exe)){throw 'The staged update has no YUMRAM.exe.'}
    $argList=@('--apply-update',('"{0}"' -f $Staging),'--target',('"{0}"' -f [string]$script:Yum.Root),'--wait-pid',[string]$PID)
    if($NoRestart){$argList+='--no-restart'}
    Start-Process -FilePath $exe -ArgumentList $argList -WorkingDirectory $Staging | Out-Null
}

function Test-YumAutoUpdateEnabled {
    # 5.15.3 (user: "whenever an update is available it should get updated"). On unless turned off in Settings.
    try{ $v=$script:Yum.Config['UpdateAutoInstall']; return (($null -eq $v) -or [bool]$v) -and [bool]$script:Yum.Config['UpdateCheckEnabled'] }catch{ return $false }
}

function Start-YumUpdateDownload {
    # Download + SHA-256 check + unpack in the background (never freezes the window); applying waits for a safe moment.
    param([Parameter(Mandatory=$true)]$Info)
    if($null -ne $script:Yum['UpdateDownloadPs']){return}
    $ps=[powershell]::Create()
    [void]$ps.AddScript({
        param($Shared,[string]$Root,$Info)
        foreach($m in 'Core\Logging.ps1','Core\Updates.ps1'){ . (Join-Path $Root $m) }
        $script:Yum=$Shared
        Install-YumUpdate -Info $Info -NoLaunch
    }.ToString()).AddArgument($script:Yum).AddArgument([string]$script:Yum.Root).AddArgument($Info)
    $script:Yum['UpdateDownloadPs']=$ps
    $script:Yum['UpdateDownloadAsync']=$ps.BeginInvoke()
}

function Receive-YumUpdateDownload {
    $ps=$script:Yum['UpdateDownloadPs'];$a=$script:Yum['UpdateDownloadAsync']
    if($null -eq $ps -or $null -eq $a -or -not $a.IsCompleted){return $null}
    $r=$null;try{$r=@($ps.EndInvoke($a))|Select-Object -Last 1}catch{}
    try{$ps.Dispose()}catch{}
    $script:Yum['UpdateDownloadPs']=$null;$script:Yum['UpdateDownloadAsync']=$null
    return $r
}

function Install-YumUpdate {
    # Downloads, verifies and stages the update, then hands over to the new YUMRAM.exe.
    # Returns @{Success;Message;Staging}. With -NoLaunch (tests) it only stages.
    param([Parameter(Mandatory=$true)]$Info,[switch]$NoLaunch,[switch]$NoRestart)
    $work=Join-Path $env:TEMP ('YUMRAM-update-'+[string]$Info.Latest)
    try{
        if(Test-Path -LiteralPath $work){Remove-Item -LiteralPath $work -Recurse -Force}
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $zip=Join-Path $work ([IO.Path]::GetFileName([string]$Info.ZipName))
        Invoke-YumUpdateRequest -Url ([string]$Info.ZipUrl) -OutFile $zip | Out-Null
        $hash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToUpperInvariant()
        if($hash -ne ([string]$Info.Sha256).ToUpperInvariant()){throw ('The download does not match its published SHA-256 (expected {0}, got {1}). Nothing was installed.' -f $Info.Sha256,$hash)}
        $staging=Join-Path $work 'staging'
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($zip,$staging)
        # Accept a zip with a single top-level folder.
        if(-not (Test-Path -LiteralPath (Join-Path $staging 'App\YUMRAM.ps1'))){
            $dirs=@(Get-ChildItem -LiteralPath $staging -Directory)
            if($dirs.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $dirs[0].FullName 'App\YUMRAM.ps1'))){$staging=$dirs[0].FullName}
        }
        if(-not (Test-Path -LiteralPath (Join-Path $staging 'App\YUMRAM.ps1'))){throw 'The update package does not contain App\YUMRAM.ps1.'}
        $ver=ConvertTo-YumVersion ([IO.File]::ReadAllText((Join-Path $staging 'VERSION')))
        if([string]$ver -ne [string]$Info.Latest){throw ('The package says version {0}, but the release is {1}. Nothing was installed.' -f $ver,$Info.Latest)}
        $exe=Join-Path $staging 'YUMRAM.exe'
        if(-not (Test-Path -LiteralPath $exe)){throw 'The update package does not contain YUMRAM.exe.'}
        try{Write-YumLog ('Update {0} downloaded and verified (SHA-256 {1}); staged in {2}.' -f $Info.Latest,$hash,$staging)}catch{}
        if($NoLaunch){return [pscustomobject]@{Success=$true;Message='Staged.';Staging=$staging}}
        Invoke-YumApplyStagedUpdate -Staging $staging -NoRestart:$NoRestart
        return [pscustomobject]@{Success=$true;Message=('Installing {0}: YUMRAM closes now and opens again in a few seconds.' -f $Info.Latest);Staging=$staging}
    }catch{
        try{Write-YumLog ('Update failed: {0}' -f $_.Exception.Message)}catch{}
        return [pscustomobject]@{Success=$false;Message=$_.Exception.Message;Staging=''}
    }
}

# --- background check (never blocks the window) ---
function Start-YumUpdateCheck {
    param([switch]$Force)
    if($null -ne $script:Yum['UpdateCheckPs']){return}
    if(-not $Force -and -not (Test-YumUpdateCheckDue)){return}
    $ps=[powershell]::Create()
    [void]$ps.AddScript({
        param($Shared,[string]$Root)
        foreach($m in 'Core\Logging.ps1','Core\Updates.ps1'){ . (Join-Path $Root $m) }
        $script:Yum=$Shared
        Get-YumUpdateInfo
    }.ToString()).AddArgument($script:Yum).AddArgument([string]$script:Yum.Root)
    $script:Yum['UpdateCheckPs']=$ps
    $script:Yum['UpdateCheckAsync']=$ps.BeginInvoke()
}

function Receive-YumUpdateCheck {
    # Called from the UI timer: returns the finished result once, else $null.
    $ps=$script:Yum['UpdateCheckPs'];$a=$script:Yum['UpdateCheckAsync']
    if($null -eq $ps -or $null -eq $a -or -not $a.IsCompleted){return $null}
    $r=$null;try{$r=@($ps.EndInvoke($a))|Select-Object -Last 1}catch{}
    try{$ps.Dispose()}catch{}
    $script:Yum['UpdateCheckPs']=$null;$script:Yum['UpdateCheckAsync']=$null
    if($null -ne $r){
        $script:Yum['UpdateInfo']=$r
        try{Update-YumConfigValue -Name UpdateLastCheck -Value ((Get-Date).ToString('o'))}catch{}
        try{Write-YumLog ('Update check: {0}' -f $r.Message)}catch{}
    }
    return $r
}
