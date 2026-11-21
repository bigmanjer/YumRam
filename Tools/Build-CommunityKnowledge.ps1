#requires -Version 5.1
<#
Builds Community\cpu-community.json from opt-in game benchmark submissions (Docs/COMMUNITY.md).

Sources (either or both):
  -ExportFile <file>   JSON array from the results server:  GET <server>/export?token=...
  -GitHubIssues        "[Benchmark]" issues (label "benchmark") in the YUMRAM repository, read through the public
                       GitHub API (no account needed; 60 requests/hour)
Every submission must pass Test-YumCommunityPayload (the same check YUMRAM uses before sending). Per CPU and per
(game class, load) the MEDIAN 1 % low per level is stored, so one odd PC cannot move the result. YUMRAM uses a
CPU only when at least 3 different submissions exist (Contributors). Publish by committing the file to main.

  powershell -NoProfile -ExecutionPolicy Bypass -File Tools\Build-CommunityKnowledge.ps1 -GitHubIssues
#>
param([string]$ExportFile='',[switch]$GitHubIssues,[string]$Repo='bigmanjer/YumRam',[string]$Out='')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if(-not $Out){$Out=Join-Path $root 'Community\cpu-community.json'}
$script:Yum=@{Config=@{Version=''}}
. (Join-Path $root 'Core\Community.ps1')

$subs=New-Object System.Collections.Generic.List[object]
if($ExportFile){ $arr=Get-Content -LiteralPath $ExportFile -Raw | ConvertFrom-Json; foreach($x in @($arr)){ [void]$subs.Add($x) } }
if($GitHubIssues){
    [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    for($page=1;$page -le 10;$page++){
        $u=('https://api.github.com/repos/{0}/issues?labels=benchmark&state=all&per_page=100&page={1}' -f $Repo,$page)
        $issues=Invoke-RestMethod -Uri $u -Headers @{'User-Agent'='YUMRAM-Community-Builder';'Accept'='application/vnd.github+json'}
        if(@($issues).Count -eq 0){break}
        foreach($i in @($issues)){
            $m=[regex]::Match([string]$i.body,'(?s)```json\s*(\{.*\})\s*```'); if(-not $m.Success){ $m=[regex]::Match([string]$i.body,'(?s)(\{.*"Kind"\s*:\s*"yumram-game-benchmark".*\})') }
            if(-not $m.Success){continue}
            try{ [void]$subs.Add(($m.Groups[1].Value | ConvertFrom-Json)) }catch{}
        }
    }
}
$ok=@();$rejected=0
foreach($s in $subs){ if(Test-YumCommunityPayload -Payload $s){$rejected++}else{$ok+=$s} }
# The same results posted twice count once.
$seen=@{};$unique=@();foreach($s in $ok){ $k=(ConvertTo-Json -InputObject $s.Results -Depth 5 -Compress)+'|'+[string]$s.Machine.Cpu; if(-not $seen.ContainsKey($k)){$seen[$k]=$true;$unique+=$s} }
function Get-Median([double[]]$v){ $s=@($v | Sort-Object); if($s.Count -eq 0){return 0}; $m=[int][math]::Floor($s.Count/2); if($s.Count % 2){return $s[$m]}; return ($s[$m-1]+$s[$m])/2 }
$cpus=@()
foreach($g in @($unique | Group-Object { Get-YumCpuKey ([string]$_.Machine.Cpu) })){
    $first=$g.Group[0].Machine
    $kn=@()
    $rows=@($g.Group | ForEach-Object { $_.Results })
    foreach($cg in @($rows | Group-Object { '{0}|{1}' -f $_.GameClass,$_.Load })){
        $parts=$cg.Name -split '\|'
        $low=[ordered]@{};foreach($lv in 'Off','Gentle','Balanced','Strong'){ $low[$lv]=[math]::Round((Get-Median @($cg.Group | ForEach-Object { [double]$_.Low1.$lv })),1) }
        $kn+=[ordered]@{GameClass=$parts[0];Load=$parts[1];Samples=$cg.Count;Low1=$low}
    }
    $cpus+=[ordered]@{Key=$g.Name;Name=[string]$first.Cpu;Cores=[int]$first.Cores;Threads=[int]$first.Threads;Hybrid=[bool]$first.Hybrid;CacheGroups=[int]$first.CacheGroups;Laptop=[bool]$first.Laptop;Contributors=$g.Count;Knowledge=$kn}
}
$doc=[ordered]@{Schema=1;Updated=(Get-Date).ToString('yyyy-MM-dd');Note='Shared YUMRAM game benchmark results, grouped by CPU. Built by Tools/Build-CommunityKnowledge.ps1 from opt-in submissions. A CPU is used by YUMRAM only with 3 or more contributors.';Cpus=$cpus}
ConvertTo-Json -InputObject $doc -Depth 8 | Set-Content -LiteralPath $Out -Encoding UTF8
Write-Host ('{0} submissions read, {1} rejected, {2} unique, {3} CPUs -> {4}' -f $subs.Count,$rejected,$unique.Count,$cpus.Count,$Out)
