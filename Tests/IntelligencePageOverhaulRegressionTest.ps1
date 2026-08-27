Set-StrictMode -Version Latest
$root = Split-Path -Parent $PSScriptRoot
$xaml = Join-Path $root 'UI\Xaml\Intelligence.xaml'
$dialogs = Join-Path $root 'UI\Dialogs.ps1'
$config = Join-Path $root 'Config\default-config.json'

[xml]$doc = Get-Content -LiteralPath $xaml -Raw
$nsmgr = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
$nsmgr.AddNamespace('x','http://schemas.microsoft.com/winfx/2006/xaml')
$required = @('RefreshView','ResearchSelected','ApplyOrganization','ClearOrganization','ManualCategory','ManualOrganizationStatus','IntelligenceResults','ActivityProgress','ActivityStatus')
foreach($name in $required){
    if($null -eq $doc.SelectSingleNode("//*[@x:Name='$name']", $nsmgr)){
        # Fallback namespace-insensitive lookup for PowerShell 5.1 XML handling.
        $hit = $doc.SelectNodes('//*[@Name]') | Where-Object { $_.GetAttribute('Name') -eq $name }
        if($null -eq $hit){ throw "Missing Intelligence control: $name" }
    }
}

$text = Get-Content -LiteralPath $dialogs -Raw
foreach($needle in @('Get-YumIntelligenceMergedRecords','Refresh-YumIntelligenceView','Set-YumManualOrganization','Save-YumIntelligenceDb','ResearchSelected','ApplyOrganization')){
    if($text.IndexOf($needle,[System.StringComparison]::Ordinal) -lt 0){ throw "Missing Intelligence page contract: $needle" }
}

$cfg = Get-Content -LiteralPath $config -Raw | ConvertFrom-Json
if([string]$cfg.Version -ne '5.2.74'){ throw "Config Version is not 5.2.74" }
if([string]$cfg.ResearchEngineVersion -ne '5.2.74'){ throw "ResearchEngineVersion is not 5.2.74" }

# PowerShell runtime regression guards. New-Object generic List instances must not be
# wrapped in @(), because PS 5.1/7.x can throw 'Argument types do not match'.
if($text -match '\$sources=New-Object System\.Collections\.Generic\.List\[object\][\s\S]{0,500}@\(\$sources\)'){ throw 'Intelligence refresh wraps a New-Object generic List in @(); use direct enumeration.' }
if($text -match '\$result\.Errors' -and $text -notmatch '\$resultErrors='){ throw 'Research result Errors access is not property-safe.' }

Write-Output 'PASS: Intelligence page controls, persistence contract, and version metadata are present.'
