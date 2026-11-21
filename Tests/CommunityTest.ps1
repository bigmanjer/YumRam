#requires -Version 5.1
# 5.15 community results: opt-in by default, nothing personal in the payload, validation, both send routes
# (server / GitHub issue) with stand-ins - no network - weekly download, matching for this PC, the builder.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'App\Bootstrap.ps1')
Initialize-YumConfig
$script:Yum.Config.Logging=$false
function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$tmp=Join-Path $env:TEMP ('yum-comm-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $tmp|Out-Null
$script:Yum.ConfigDirectory=$tmp;$script:Yum.ConfigFile=(Join-Path $tmp 'config.json')
try{
    # 1. Defaults: sharing is opt-in; using shared results is on.
    $def=Get-Content (Join-Path $root 'Config\default-config.json') -Raw | ConvertFrom-Json
    Assert-That (-not [bool]$def.CommunityShareEnabled) 'Sharing must be OFF by default.'
    Assert-That ([bool]$def.CommunityUseShared) 'Using shared results is on by default.'
    Assert-That (-not [bool]$def.CommunityAsked) 'Not asked yet.'

    # 2. Payload: only benchmark numbers and machine facts; nothing personal.
    $kn=[pscustomobject]@{Knowledge=@(
        [pscustomobject]@{GameClass='Medium';GameKey='Medium';Hog='Saturating';GameShareNoHog=24;Low1ByLevel=[pscustomobject]@{Off=3;Gentle=8;Balanced=18;Strong=102};AvgByLevel=[pscustomobject]@{Off=4;Gentle=23;Balanced=150;Strong=176}}
        [pscustomobject]@{GameClass='Heavy';GameKey='Heavy';Hog='Bursty';GameShareNoHog=43;Low1ByLevel=[pscustomobject]@{Off=7;Gentle=9;Balanced=14;Strong=12}})}
    $p=New-YumCommunityPayload -Knowledge $kn
    Assert-That ($null -ne $p -and @($p.Results).Count -eq 2) 'Payload built from this PC''s knowledge.'
    Assert-That ((Test-YumCommunityPayload -Payload $p) -eq '') 'Own payload passes validation.'
    $text=ConvertTo-YumCommunityText -Payload $p
    foreach($s in @($env:USERNAME,$env:COMPUTERNAME,$env:USERPROFILE,$env:USERDOMAIN)){ if($s -and $s.Length -ge 3){ Assert-That ($text.IndexOf($s,[StringComparison]::OrdinalIgnoreCase) -lt 0) ("Payload must not contain '{0}'." -f $s) } }
    foreach($k in 'Path','Process','User','Computer','Email','Guid','Id"'){ Assert-That ($text -notmatch ('"{0}' -f $k)) ("Payload must not have a {0} field." -f $k) }
    Assert-That ($text -match '"Cpu"' -and $text -match '"Low1"') 'Payload has CPU and frame rates.'

    # 3. Validation rejects junk and fakes.
    $bad=ConvertTo-Json -InputObject $p -Depth 6 | ConvertFrom-Json; $bad.Results[0].Low1.Strong=99999
    Assert-That ((Test-YumCommunityPayload -Payload $bad) -match 'impossible') 'Impossible frame rates are rejected.'
    $bad2=ConvertTo-Json -InputObject $p -Depth 6 | ConvertFrom-Json; $bad2.Machine.Cores=64; $bad2.Machine.Threads=8
    Assert-That ((Test-YumCommunityPayload -Payload $bad2) -match 'core') 'Impossible core counts are rejected.'
    Assert-That ((Test-YumCommunityPayload -Payload $null) -ne '') 'Nothing is rejected.'

    # 4. Sending: GitHub route without a server, server route with one. Stand-ins, no network.
    $script:opened='';$r=Send-YumCommunityResults -Payload $p -Opener { param($u) $script:opened=$u }
    Assert-That ($r.Success -and $script:opened -like 'https://github.com/*/issues/new?template=benchmark.yml&title=*&results=*') 'Without a server: pre-filled GitHub issue.'
    Assert-That ($script:opened.Length -le 8000) 'Issue link fits GitHub''s URL limit.'
    $script:Yum.Config['CommunityEndpoint']='https://results.example.test'
    $script:posted=$null;$r2=Send-YumCommunityResults -Payload $p -Poster { param($u,$b) $script:posted=@($u,$b); 'ok' }
    Assert-That ($r2.Success -and $script:posted[0] -eq 'https://results.example.test/submit' -and $script:posted[1] -eq $text) 'With a server: exactly the shown text is POSTed to /submit.'
    $r3=Send-YumCommunityResults -Payload $p -Poster { param($u,$b) throw 'offline' }
    Assert-That (-not $r3.Success -and $r3.Reason -match 'offline') 'A failed send is reported.'
    $script:Yum.Config['CommunityEndpoint']=''
    $script:posted=$null;$r4=Send-YumCommunityResults -Payload $bad -Poster { param($u,$b) $script:posted=1 } -Opener { param($u) $script:posted=1 }
    Assert-That (-not $r4.Success -and $null -eq $script:posted) 'Invalid data is never sent.'

    # 5. Weekly download (stand-in), only when allowed.
    $feed=[ordered]@{Schema=1;Updated='2026-11-21';Cpus=@(
        [ordered]@{Key=(Get-YumCpuKey 'Test CPU 9000');Name='Test CPU 9000';Cores=8;Threads=16;Hybrid=$false;CacheGroups=2;Laptop=$true;Contributors=4;Knowledge=@([ordered]@{GameClass='Medium';Load='Saturating';Samples=4;Low1=[ordered]@{Off=3;Gentle=9;Balanced=20;Strong=95}})}
        [ordered]@{Key='rare cpu';Name='Rare CPU';Cores=8;Threads=16;Hybrid=$false;CacheGroups=2;Laptop=$true;Contributors=2;Knowledge=@()})}
    $json=ConvertTo-Json -InputObject $feed -Depth 8
    $script:Yum.Config['CommunityUseShared']=$false
    Assert-That (-not (Update-YumCommunityKnowledge -Force -Getter { param($u) $json })) 'Switched off: nothing is downloaded.'
    $script:Yum.Config['CommunityUseShared']=$true
    Assert-That (Update-YumCommunityKnowledge -Force -Getter { param($u) $json }) 'Download saves the file.'
    Assert-That (-not (Update-YumCommunityKnowledge -Getter { param($u) throw 'should not be called' })) 'Not again within a week.'
    Assert-That (-not (Update-YumCommunityKnowledge -Force -Getter { param($u) '{"Schema":99}' })) 'A file in the wrong format is not saved.'

    # 6. Matching for this PC: exact CPU, then same layout; >= 3 contributors.
    $mine=[pscustomobject]@{Cpu='Test CPU 9000';CpuKey=(Get-YumCpuKey 'Test CPU 9000');Cores=8;Threads=16;Hybrid=$false;CacheGroups=2;Laptop=$true}
    $ck=Get-YumCommunityKnowledgeForThisPc -Machine $mine
    Assert-That ($null -ne $ck -and $ck.Contributors -eq 4 -and $ck.How -eq 'your CPU') 'Same CPU found.'
    $other=[pscustomobject]@{Cpu='Other CPU';CpuKey='other cpu';Cores=8;Threads=16;Hybrid=$false;CacheGroups=2;Laptop=$true}
    $ck2=Get-YumCommunityKnowledgeForThisPc -Machine $other
    Assert-That ($null -ne $ck2 -and $ck2.How -match 'laid out') 'Same layout used when the exact CPU is missing.'
    $lonely=[pscustomobject]@{Cpu='Lonely';CpuKey='lonely';Cores=4;Threads=4;Hybrid=$false;CacheGroups=1;Laptop=$false}
    Assert-That ($null -eq (Get-YumCommunityKnowledgeForThisPc -Machine $lonely)) 'No match -> nothing.'
    $adv=Get-YumGamingAdvice -Knowledge $ck -CurrentLevel 'Balanced' -GameAloneShare 40 -OtherShare 70
    Assert-That ($null -ne $adv -and $adv.Level -eq 'Strong' -and $adv.Reason -match 'shared by 4 people') 'Advice from shared results says where it came from.'

    # 7. Builder: medians, rejects junk, counts contributors, dedupes.
    $subs=@(); foreach($v in 90,100,400){ $s=ConvertTo-Json -InputObject $p -Depth 6 | ConvertFrom-Json; $s.Results[0].Low1.Strong=$v; $s.Machine.Cpu='Test CPU 9000'; $subs+=$s }
    $subs+=($subs[0]); $junk=ConvertTo-Json -InputObject $bad -Depth 6 | ConvertFrom-Json; $subs+=$junk
    $ex=Join-Path $tmp 'export.json'; ConvertTo-Json -InputObject $subs -Depth 8 | Set-Content -LiteralPath $ex -Encoding UTF8
    $out=Join-Path $tmp 'community.json'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'Tools\Build-CommunityKnowledge.ps1') -ExportFile $ex -Out $out | Out-Null
    $built=Get-Content -LiteralPath $out -Raw | ConvertFrom-Json
    $c=@($built.Cpus)[0]
    Assert-That ($c.Contributors -eq 3) ('Duplicate and junk not counted: {0} contributors.' -f $c.Contributors)
    $med=[double](@($c.Knowledge | Where-Object { $_.Load -eq 'Saturating' })[0].Low1.Strong)
    Assert-That ($med -eq 100) ('Median keeps one odd result (400) from moving the advice: {0}.' -f $med)

    # 8. Wiring.
    $xaml=[IO.File]::ReadAllText((Join-Path $root 'UI\Xaml\Settings.xaml'))
    foreach($n in 'CommunityShareEnabled','CommunityUseShared','CommunityShareNow','CpuBench','CpuCareAdaptive'){ Assert-That ($xaml -match ('x:Name="{0}"' -f $n)) ("Settings has {0}." -f $n) }
    Assert-That (Test-Path (Join-Path $root '.github\ISSUE_TEMPLATE\benchmark.yml')) 'GitHub benchmark form exists.'
    Assert-That ((Get-Content (Join-Path $root 'Community\cpu-community.json') -Raw | ConvertFrom-Json).Schema -eq 1) 'Shared file exists in the repository.'
}finally{ Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host 'CommunityTest passed.'
