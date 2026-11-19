#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$text=Get-Content -LiteralPath (Join-Path $root 'Core\Research.ps1') -Raw

# This exact defect is documented by PowerShell's own issue tracker:
# @($list) can throw System.ArgumentException "Argument types do not match"
# for a List[object] created with New-Object on Windows PowerShell 5.1.
foreach($forbidden in @(
    '@($script:YumResearchRegistryInventory)',
    '@($script:YumResearchAppxInventory)',
    '@($script:YumResearchServiceInventory)'
)){
    if($text.Contains($forbidden)){
        throw "Forbidden PS5.1 Generic List array-subexpression found: $forbidden"
    }
}
if(-not $text.Contains('$script:YumResearchRegistryInventory.ToArray()')){
    throw 'Registry inventory must use ToArray() before enumeration.'
}
if(-not $text.Contains('$script:YumResearchAppxInventory.ToArray()')){
    throw 'AppX inventory must use ToArray() before enumeration.'
}
if(-not $text.Contains('$script:YumResearchServiceInventory.ToArray()')){
    throw 'Service inventory must use ToArray() before enumeration.'
}
Write-Host 'ResearchPowerShell51ArgumentTypesRegressionTest PASSED.'
