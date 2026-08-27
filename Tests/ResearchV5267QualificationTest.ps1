#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$research=Join-Path $root 'Core\Research.ps1'
$script:Yum=[pscustomobject]@{
    Root=$root
    ConfigDirectory=$root
    Config=[pscustomobject]@{
        Version='5.2.74'
        ResearchEngineVersion='5.2.74'
        EnableOnlineResearch=$true
        ResearchRequestTimeoutSeconds=2
        OnlineResearchProvider={
            param($Name,$Publisher,$Product)
            [pscustomobject]@{
                Success=$true
                BestScore=91
                VerifiedLinks=@('https://github.com/example/project')
                VerifiedCount=1
                GitHubCount=1
                RedditCount=0
                Results=@([pscustomobject]@{Title='Example';Link='https://github.com/example/project'})
            }
        }
    }
}
. $research

$record=[pscustomobject]@{Name='Example';Risk='Review';Category='Apps'}
Ensure-YumResearchRecordSchema -Record $record | Out-Null
foreach($required in @('ResearchComplete','ResearchRunDisposition','ResearchRunResolved','ResearchRunOnline')){
    if($null -eq $record.PSObject.Properties[$required]){throw "Research schema missing $required"}
}

$online=Get-YumOnlineResearch -Name 'Example' -Publisher 'Example Corp' -Product 'Example App'
if(-not $online.Success){throw "Injected online provider did not succeed: $($online.Error)"}
if($online.BestScore -ne 91){throw "Injected provider score was not preserved: $($online.BestScore)"}
if(@($online.VerifiedLinks).Count -ne 1){throw 'Injected provider verified-link collection was not preserved.'}

$record2=[pscustomobject]@{Name='Minimal Record';Risk='Review';Category='Apps'}
Write-YumResearchLiveSnapshot -RunId 'qualification' -Completed 0 -Total 1 -Records @($record2)
$live=Join-Path $root 'research-live-results-qualification-000000.json'
if(-not(Test-Path -LiteralPath $live)){throw 'Research live snapshot was not written for a minimal record.'}
Remove-Item -LiteralPath $live -Force -ErrorAction SilentlyContinue

Write-Host 'ResearchV5267QualificationTest: PASS'

# Regression: Windows PowerShell 5.1 can throw
# "Argument types do not match" for @($newObjectList).
# Research must never use that pattern on its live Generic List inventories.
$researchText=Get-Content -LiteralPath $research -Raw
foreach($forbidden in @(
    '@($script:YumResearchRegistryInventory)',
    '@($script:YumResearchAppxInventory)',
    '@($script:YumResearchServiceInventory)'
)){
    if($researchText.Contains($forbidden)){
        throw "PowerShell 5.1 Generic List regression remains: $forbidden"
    }
}
foreach($requiredSafe in @(
    'foreach($item in $script:YumResearchRegistryInventory.ToArray())',
    'foreach($pkg in $script:YumResearchAppxInventory.ToArray())',
    'foreach($svc in $script:YumResearchServiceInventory.ToArray())'
)){
    if(-not $researchText.Contains($requiredSafe)){
        throw "Expected PS5.1-safe Generic List enumeration missing: $requiredSafe"
    }
}
Write-Host 'ResearchV5268QualificationTest: PS5.1 Generic List inventory regression: PASS'

