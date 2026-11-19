$ErrorActionPreference='Stop'
# 5.3.0: the 5.2.x file had its backslashes turned into real newlines ("\N" / "\n") and depended on
# NVIDIA/Proton being installed. Uses executables present on every Windows install instead.
# Regression: Test-Path on the full command line threw "Illegal characters in path" and the
# function returned '' for any service/startup entry carrying quoted arguments.
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Core\Research.ps1')
$sys=Join-Path $env:windir 'System32'
$normalized=Get-YumResearchExecutablePath -Path ('"{0}\cmd.exe" /c "echo <x>" -f "C:\ProgramData\x.log"' -f $sys)
if($normalized -ne "$sys\cmd.exe"){throw "Quoted command-line path normalization failed: '$normalized'"}
$normalized2=Get-YumResearchExecutablePath -Path ('{0}\svchost.exe "----ms-protocol:ms-encodedlaunch:App?ContractId=Windows.StartupTask&TaskId=Some App"' -f $sys)
if($normalized2 -ne "$sys\svchost.exe"){throw "Unquoted executable normalization failed: '$normalized2'"}
$plain=Get-YumResearchExecutablePath -Path "$sys\notepad.exe"
if($plain -ne "$sys\notepad.exe"){throw "Plain executable path was not returned: '$plain'"}
# Must not throw on characters that are illegal in paths.
$invalid=Get-YumResearchFileEvidence -Path ('{0}\svchost.exe "----ms-protocol:bad<path>"' -f $sys)
Write-Host 'PASS Research path normalization is command-line safe.'
