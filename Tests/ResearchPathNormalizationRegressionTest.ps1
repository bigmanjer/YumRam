$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Core\Research.ps1')
$normalized=Get-YumResearchExecutablePath -Path '"C:\Program Files
VIDIA Corporation
vContainer
vcontainer.exe" -s NvContainerLocalSystem -a -f "C:\ProgramData\x.log"'
if($normalized -ne 'C:\Program Files
VIDIA Corporation
vContainer
vcontainer.exe'){throw "Command-line path normalization failed: $normalized"}
$normalized2=Get-YumResearchExecutablePath -Path 'C:\Program Files\Proton\VPN\ProtonVPN.Launcher.exe "----ms-protocol:ms-encodedlaunch:App?ContractId=Windows.StartupTask&TaskId=Proton VPN"'
if($normalized2 -ne 'C:\Program Files\Proton\VPN\ProtonVPN.Launcher.exe'){throw "Unquoted executable normalization failed: $normalized2"}
$invalid=Get-YumResearchFileEvidence -Path 'C:\Program Files\Proton\VPN\ProtonVPN.Launcher.exe "----ms-protocol:bad<path>"'
Write-Host 'PASS Research path normalization is command-line safe.'
