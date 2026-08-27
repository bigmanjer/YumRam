#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Core\Logging.ps1') | Out-Null
$script:Yum=[pscustomobject]@{Root=$root;ConfigDirectory=$root;Config=[pscustomobject]@{ResearchEngineVersion='5.2.37';ResearchCacheMaxAgeDays=14};IntelligenceDbFile=(Join-Path $root 'Tests\tmp-intelligence-db.json')}
. (Join-Path $root 'Core\Intelligence.ps1') | Out-Null
. (Join-Path $root 'Core\Research.ps1') | Out-Null
$cachePath=Get-YumResearchCachePath
$ok1=Clear-YumResearchCache
$ok2=Clear-YumIntelligenceDb
if(-not $ok1 -or -not $ok2){throw 'Cache lifecycle clear operations failed.'}
if(Test-Path -LiteralPath $cachePath){throw 'Research cache still exists after clear.'}
if(Test-Path -LiteralPath $script:Yum.IntelligenceDbFile){throw 'Intelligence DB still exists after clear.'}
$identitySignals=@(@($true,$false,$false,$false,$false)|Where-Object{$_})
if($identitySignals.Count -ne 1){throw 'Single identity signal Count regression failed.'}
$identitySignals=@(@($true,$true,$false,$true,$false)|Where-Object{$_})
if($identitySignals.Count -ne 3){throw 'Multiple identity signals Count regression failed.'}
$terms=@(@('Publisher','Product','Name')|Where-Object{$_})
if($terms.Count -ne 3){throw 'Research term Count regression failed.'}
Write-Output 'Intelligence cache lifecycle regression PASS'
