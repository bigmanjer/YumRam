#requires -Version 5.1
# 5.15: community game results - opt-in sharing and shared learning.
#
# What a user can share (only if THEY choose, after seeing the exact text): their CPU model, cores/threads,
# hybrid / cache groups, laptop or desktop, Windows build, YUMRAM version and the numbers from "Measure games"
# (frame rates per CPU care level and load). Never: program names, paths, user or PC names, IDs, location.
#
# How it travels:
#   - CommunityEndpoint set (the YUMRAM results server, Server/community-worker.js): an HTTPS POST of that text.
#   - Otherwise: a pre-filled GitHub "Benchmark results" issue opens in the browser; the user presses Create.
# How everyone benefits: once a week YUMRAM downloads Community/cpu-community.json from GitHub (a public file;
# the request carries nothing about you, like the update check). When this PC has not measured games itself,
# CPU care uses the results of other people with the same CPU - only when at least 3 people agree.

$script:YumCommunitySchema=1

function Get-YumCommunityConfig {
    $c=$script:Yum.Config
    $get={param($n,$d) try{ if($c.Contains($n) -and $null -ne $c[$n]){ return $c[$n] } }catch{}; return $d}
    [pscustomobject]@{
        Share=[bool](& $get 'CommunityShareEnabled' $false)
        UseShared=[bool](& $get 'CommunityUseShared' $true)
        Endpoint=[string](& $get 'CommunityEndpoint' '')
        FeedUrl=[string](& $get 'CommunityFeedUrl' 'https://raw.githubusercontent.com/bigmanjer/YumRam/main/Community/cpu-community.json')
        Repo=[string](& $get 'UpdateRepository' 'bigmanjer/YumRam')
    }
}

function Get-YumCpuKey { param([string]$Name) return (([string]$Name).Trim().ToLowerInvariant() -replace '\s+',' ' -replace '\(r\)|\(tm\)|\(c\)','') }

function Get-YumCommunityMachine {
    $p=Get-YumCpuProfile
    $build='';try{ $build=[string][Environment]::OSVersion.Version.Build }catch{}
    $win=if([int]$build -ge 22000){'Windows 11'}else{'Windows 10'}
    [pscustomobject]@{Cpu=[string]$p.Name;CpuKey=(Get-YumCpuKey $p.Name);Cores=[int]$p.Cores;Threads=[int]$p.Logical;Hybrid=[bool]$p.Hybrid;CacheGroups=[int]$p.L3Groups;Laptop=[bool]$p.Laptop;Windows=('{0} build {1}' -f $win,$build)}
}

function New-YumCommunityPayload {
    # The exact text that would be shared. $Knowledge = this PC's cpu-knowledge.json (Get-YumCpuKnowledge).
    param($Knowledge,$Machine=(Get-YumCommunityMachine))
    if($null -eq $Knowledge){return $null}
    $rows=@($Knowledge.Knowledge | Where-Object { $null -ne $_ -and $null -ne $_.PSObject.Properties['Low1ByLevel'] } | ForEach-Object {
        [ordered]@{GameClass=[string]$_.GameClass;Game=[string]$_.GameKey;Load=[string]$_.Hog;GameCpuShare=[double]$_.GameShareNoHog
            Low1=[ordered]@{Off=[double]$_.Low1ByLevel.Off;Gentle=[double]$_.Low1ByLevel.Gentle;Balanced=[double]$_.Low1ByLevel.Balanced;Strong=[double]$_.Low1ByLevel.Strong}
            Avg=$(if($null -ne $_.PSObject.Properties['AvgByLevel']){[ordered]@{Off=[double]$_.AvgByLevel.Off;Gentle=[double]$_.AvgByLevel.Gentle;Balanced=[double]$_.AvgByLevel.Balanced;Strong=[double]$_.AvgByLevel.Strong}}else{$null})} })
    if($rows.Count -eq 0){return $null}
    $ver='';try{$ver=[string]$script:Yum.Config.Version}catch{}
    return [ordered]@{Schema=$script:YumCommunitySchema;Kind='yumram-game-benchmark';App=$ver;Day=(Get-Date).ToUniversalTime().ToString('yyyy-MM-dd');Machine=$Machine;Results=$rows}
}

function Test-YumCommunityPayload {
    # Rejects anything that is not plausible benchmark data (also used by the aggregator for incoming data).
    param($Payload)
    try{
        if($null -eq $Payload -or [int]$Payload.Schema -ne $script:YumCommunitySchema -or [string]$Payload.Kind -ne 'yumram-game-benchmark'){return 'wrong format'}
        $m=$Payload.Machine
        if([string]::IsNullOrWhiteSpace([string]$m.Cpu) -or ([string]$m.Cpu).Length -gt 120){return 'CPU name missing or too long'}
        if([int]$m.Threads -lt 1 -or [int]$m.Threads -gt 512 -or [int]$m.Cores -lt 1 -or [int]$m.Cores -gt [int]$m.Threads){return 'impossible core counts'}
        $rs=@($Payload.Results); if($rs.Count -lt 1 -or $rs.Count -gt 40){return 'wrong number of results'}
        foreach($r in $rs){
            if([string]$r.GameClass -notin @('Light','Medium','Heavy')){return 'bad game class'}
            if([string]$r.Load -notin @('Half','Saturating','Bursty')){return 'bad load'}
            foreach($lv in 'Off','Gentle','Balanced','Strong'){ $v=[double]$r.Low1.$lv; if($v -le 0 -or $v -gt 5000){return ('impossible frame rate for {0}' -f $lv)} }
        }
        return ''
    }catch{ return ('unreadable: {0}' -f $_.Exception.Message) }
}

function ConvertTo-YumCommunityText { param($Payload) return (ConvertTo-Json -InputObject $Payload -Depth 6) }

function Send-YumCommunityResults {
    # Sends only what Test-YumCommunityPayload accepts. Returns @{Success;Reason}. -Opener replaces Start-Process (tests).
    param([Parameter(Mandatory)]$Payload,[scriptblock]$Poster,[scriptblock]$Opener)
    $bad=Test-YumCommunityPayload -Payload $Payload
    if($bad){ return [pscustomobject]@{Success=$false;Reason=('Not sent: {0}.' -f $bad)} }
    $cfg=Get-YumCommunityConfig
    $text=ConvertTo-YumCommunityText -Payload $Payload
    if($cfg.Endpoint -match '^https://'){
        if($null -eq $Poster){ $Poster={ param($url,$body)
            [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            $wc=New-Object System.Net.WebClient; try{ $wc.Headers['User-Agent']='YUMRAM-Community'; $wc.Headers['Content-Type']='application/json'; return $wc.UploadString($url,'POST',$body) }finally{$wc.Dispose()} } }
        try{ [void](& $Poster ($cfg.Endpoint.TrimEnd('/')+'/submit') $text); try{Write-YumLog ('Community: shared game benchmark results ({0}, {1} results).' -f $Payload.Machine.Cpu,@($Payload.Results).Count)}catch{}; return [pscustomobject]@{Success=$true;Reason='Thank you - your results were shared. Everyone with a similar CPU benefits from the next community update.'} }
        catch{ return [pscustomobject]@{Success=$false;Reason=('Could not reach the YUMRAM results server: {0}' -f $_.Exception.Message)} }
    }
    # No server configured: a pre-filled GitHub issue (the user sees it and presses Create).
    $title=('[Benchmark] {0}' -f $Payload.Machine.Cpu)
    $url=('https://github.com/{0}/issues/new?template=benchmark.yml&title={1}&results={2}' -f $cfg.Repo,[uri]::EscapeDataString($title),[uri]::EscapeDataString($text))
    if($url.Length -gt 8000){ $compact=ConvertTo-Json -InputObject $Payload -Depth 6 -Compress; $url=('https://github.com/{0}/issues/new?template=benchmark.yml&title={1}&results={2}' -f $cfg.Repo,[uri]::EscapeDataString($title),[uri]::EscapeDataString($compact)) }
    if($null -eq $Opener){ $Opener={ param($u) Start-Process $u } }
    & $Opener $url
    try{Write-YumLog 'Community: opened a pre-filled GitHub "Benchmark results" issue in the browser.'}catch{}
    return [pscustomobject]@{Success=$true;Reason='Your browser shows the results on GitHub - press Create to share them (a GitHub account is needed). Thank you!'}
}

# ---------------------------------------------------------------- receiving: shared results for this CPU
function Get-YumCommunityFilePath { return (Join-Path ([string]$script:Yum.ConfigDirectory) 'cpu-community.json') }

function Update-YumCommunityKnowledge {
    # Downloads the public community file at most once a week (or -Force). Safe to call often.
    param([switch]$Force,[scriptblock]$Getter)
    $cfg=Get-YumCommunityConfig
    if(-not $cfg.UseShared){return $false}
    $path=Get-YumCommunityFilePath
    if(-not $Force -and (Test-Path -LiteralPath $path)){ if(((Get-Date)-(Get-Item -LiteralPath $path).LastWriteTime).TotalDays -lt 7){return $false} }
    if($null -eq $Getter){ $Getter={ param($u) [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; $wc=New-Object System.Net.WebClient; try{ $wc.Headers['User-Agent']='YUMRAM-Community'; return $wc.DownloadString($u) }finally{$wc.Dispose()} } }
    try{
        $text=[string](& $Getter $cfg.FeedUrl)
        $doc=$text | ConvertFrom-Json   # validate before saving
        if($null -eq $doc -or [int]$doc.Schema -ne $script:YumCommunitySchema){ throw 'unexpected format' }
        Set-Content -LiteralPath $path -Value $text -Encoding UTF8
        $script:Yum['CommunityKnowledge']=$null
        try{Write-YumLog ('Community: downloaded shared game results ({0} CPUs).' -f @($doc.Cpus).Count)}catch{}
        return $true
    }catch{
        # Touch the old file so a failing network is not retried every minute.
        try{ if(Test-Path -LiteralPath $path){ (Get-Item -LiteralPath $path).LastWriteTime=Get-Date } }catch{}
        $why=[string]$_.Exception.Message; if($_.Exception.InnerException){$why=[string]$_.Exception.InnerException.Message}
        $why=if($why -match '404'){'nothing has been published yet'}elseif($why -match 'format'){'the file had an unexpected format'}else{('no connection: {0}' -f ($why -replace '^.*?: \"?',''))}
        try{Write-YumLog ('Community: shared results not updated - {0}. Trying again in a week.' -f $why)}catch{}
        return $false
    }
}

function Get-YumCommunityKnowledgeForThisPc {
    # Knowledge in the same shape as cpu-knowledge.json, from other people with this CPU (>= 3 contributors).
    param($Doc,$Machine=(Get-YumCommunityMachine),[int]$MinContributors=3)
    if($null -eq $Doc){
        $cfg=Get-YumCommunityConfig; if(-not $cfg.UseShared){return $null}
        $p=Get-YumCommunityFilePath; if(-not (Test-Path -LiteralPath $p)){return $null}
        try{ $Doc=Get-Content -LiteralPath $p -Raw | ConvertFrom-Json }catch{ return $null }
    }
    $cpus=@($Doc.Cpus | Where-Object { $null -ne $_ -and [int]$_.Contributors -ge $MinContributors })
    $match=@($cpus | Where-Object { [string]$_.Key -eq [string]$Machine.CpuKey })
    $how='your CPU'
    if($match.Count -eq 0){
        # Same layout (cores, threads, hybrid, cache groups, laptop/desktop) is the next best thing.
        $match=@($cpus | Where-Object { [int]$_.Cores -eq [int]$Machine.Cores -and [int]$_.Threads -eq [int]$Machine.Threads -and [bool]$_.Hybrid -eq [bool]$Machine.Hybrid -and [int]$_.CacheGroups -eq [int]$Machine.CacheGroups -and [bool]$_.Laptop -eq [bool]$Machine.Laptop } | Sort-Object { -[int]$_.Contributors })
        $how='CPUs laid out like yours'
    }
    if($match.Count -eq 0){return $null}
    $c=$match[0]
    return [pscustomobject]@{Source='community';Contributors=[int]$c.Contributors;How=$how;Machine=[string]$c.Name
        Knowledge=@($c.Knowledge | ForEach-Object { [pscustomobject]@{GameClass=[string]$_.GameClass;GameKey=[string]$_.GameClass;Hog=[string]$_.Load;Low1ByLevel=$_.Low1} })}
}

function Start-YumCommunityFetch {
    # Weekly download of the shared results file, in its own background runspace (never blocks the window or CPU care).
    try{
        $cfg=Get-YumCommunityConfig; if(-not $cfg.UseShared){return}
        $p=Get-YumCommunityFilePath
        if((Test-Path -LiteralPath $p) -and ((Get-Date)-(Get-Item -LiteralPath $p).LastWriteTime).TotalDays -lt 7){return}
        $ps=[powershell]::Create()
        [void]$ps.AddScript({
            param($Shared,[string]$Root)
            foreach($m in 'Core\Logging.ps1','Core\Community.ps1'){ . (Join-Path $Root $m) }
            $script:Yum=$Shared
            [void](Update-YumCommunityKnowledge)
        }.ToString()).AddArgument($script:Yum).AddArgument([string]$script:Yum.Root)
        $script:Yum['CommunityFetchPs']=$ps
        $script:Yum['CommunityFetchAsync']=$ps.BeginInvoke()
    }catch{ try{Write-YumLogException -Context 'Community fetch start failed' -Exception $_.Exception}catch{} }
}