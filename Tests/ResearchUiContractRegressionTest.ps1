$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$intel=Join-Path $root 'Core\Intelligence.ps1'
$dialogs=Join-Path $root 'UI\Dialogs.ps1'
$text=Get-Content $intel -Raw
if($text -notmatch "Signature='Unknown'"){throw 'Intelligence record schema does not define Signature.'}
$text2=Get-Content $dialogs -Raw
if($text2 -match '\$r\.Signature\b'){throw 'Dialogs contains unsafe direct r.Signature property access.'}
if($text2 -notmatch 'Ensure-YumIntelligenceRecordSchema -Record \$r'){throw 'Dialogs selection handler does not normalize record schema.'}
Write-Output 'Research UI contract regression test PASS.'
