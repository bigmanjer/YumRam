#requires -Version 5.1
# 5.4 research regressions (all measured on a real PC before the fix):
#  - Get-YumResearchSourceTrust assigned $host (read-only) and always returned 0: online verification never worked.
#  - Token overlap used Select-Object -Unique (quadratic): one vendor page took 85 s.
#  - WinGet ran one winget.exe per item (~3.5 s) and its exact-name flag was never set.
#  - Store/System AppX packages could not be matched exactly, so they stayed Unknown.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'App\Bootstrap.ps1')
Initialize-YumConfig
. (Join-Path $root 'Core\Research.ps1')
$script:Yum.Config.Logging=$false

# Trust scoring.
if((Get-YumResearchSourceTrust -Url 'https://learn.microsoft.com/windows') -lt 90){throw 'microsoft.com is not trusted (trust scoring broken).'}
if((Get-YumResearchSourceTrust -Url 'https://www.logitechg.com/en-us/software/ghub' -Publisher 'Logitech') -lt 80){throw "Publisher's own site is not trusted."}
if((Get-YumResearchSourceTrust -Url 'https://www.bing.com/search?q=x') -ne 0){throw 'Search engine result pages must never be trusted.'}
if((Get-YumResearchSourceTrust -Url 'https://random-blog.example.net/x' -Publisher 'Logitech') -ge 80){throw 'Unrelated site trusted as publisher site.'}

# Token overlap: correct and fast on large text.
if((Get-YumResearchTokenOverlap -Left 'Google Chrome' -Right 'Chrome browser by Google') -ne 100){throw 'Token overlap scoring is wrong.'}
$big=('lorem ipsum dolor sit amet ' * 40000) + ' logitech hub'
$sw=[Diagnostics.Stopwatch]::StartNew()
[void](Get-YumResearchTokenOverlap -Left 'Logitech G HUB' -Right $big)
if($sw.Elapsed.TotalSeconds -gt 5){throw ('Token overlap on ~1 MB took {0:N1}s (quadratic de-duplication is back).' -f $sw.Elapsed.TotalSeconds)}

# Publisher names from package DNs.
if((Get-YumAppxPublisherName -PublisherDn 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US' -PackageName 'X') -ne 'Microsoft Corporation'){throw 'O= publisher not parsed.'}
if((Get-YumAppxPublisherName -PublisherDn 'CN=82419BD3-B8A7-4FD6-9731-D95DB6175B11' -PackageName 'DTSInc.DTSXUltra') -ne 'DTSInc'){throw 'GUID publisher fallback not parsed.'}

# A built-in Windows package must match exactly as Windows-verified.
$sys=@(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { [string]$_.SignatureKind -eq 'System' } | Select-Object -First 1)
if($sys.Count -gt 0){
    $ev=@(Get-YumAppxResearch -Name $sys[0].Name -Path $sys[0].PackageFullName)
    $hit=@($ev | Where-Object { [bool]$_.ExactPackage -and [string]$_.SignatureKind -eq 'System' })
    if($hit.Count -eq 0 -or [int]$hit[0].Score -ne 100){throw "System package $($sys[0].Name) was not matched exactly."}
} else { Write-Warning 'No AppX packages visible; exact-package check skipped.' }

# WinGet inventory loads once and gives exact matches.
if(Get-Command winget.exe -ErrorAction SilentlyContinue){
    $script:YumResearchWinGetInventory=$null
    $inv=Get-YumWinGetInventory
    if($inv.Count -lt 5){throw "WinGet inventory parsed only $($inv.Count) entries."}
    $first=$inv[0]
    $r=Get-YumWinGetResearch -Name $first.Name
    if($null -eq $r -or -not $r.ExactName){throw "WinGet exact match failed for '$($first.Name)'."}
} else { Write-Warning 'winget.exe not available; WinGet check skipped.' }
Write-Output 'PASS: trust scoring, fast overlap, AppX identity, and WinGet inventory work.'
