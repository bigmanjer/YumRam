#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Root
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Read-TestUtf8 {
    param([Parameter(Mandatory=$true)][string]$Path)
    $enc = [System.Text.UTF8Encoding]::new($false,$true)
    return [System.IO.File]::ReadAllText($Path,$enc)
}
$Root = $Root.Trim().Trim('"')
$Root = [System.IO.Path]::GetFullPath($Root)
$Root = (Resolve-Path -LiteralPath $Root).Path
$errors = New-Object System.Collections.Generic.List[string]
$log = Join-Path $Root 'YUMRAM.log'
function Add-CheckError { param([string]$Message) [void]$errors.Add($Message) }
$psFiles = Get-ChildItem -LiteralPath $Root -Filter '*.ps1' -File -Recurse
foreach($file in $psFiles){
    try {
        $tokens=$null; $parseErrors=$null
        [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
        if($parseErrors.Count -gt 0){ foreach($e in $parseErrors){ Add-CheckError ("PS PARSE: {0}({1},{2}) {3}" -f $file.FullName,$e.Extent.StartLineNumber,$e.Extent.StartColumnNumber,$e.Message) } }
    } catch { Add-CheckError ("PS CHECK FAILED: {0} :: {1}" -f $file.FullName,$_.Exception.Message) }
}
$xamlDir = Join-Path $Root 'UI\Xaml'
if(-not(Test-Path -LiteralPath $xamlDir)){ Add-CheckError "Missing XAML directory: $xamlDir" }
else {
    foreach($file in (Get-ChildItem -LiteralPath $xamlDir -Filter '*.xaml' -File)){
        try { [xml](Read-TestUtf8 -Path $file.FullName) | Out-Null } catch { Add-CheckError ("XAML INVALID: {0} :: {1}" -f $file.FullName,$_.Exception.Message) }
    }
}
try { Get-Content -LiteralPath (Join-Path $Root 'Config\default-config.json') -Raw | ConvertFrom-Json | Out-Null } catch { Add-CheckError ("JSON INVALID: {0}" -f $_.Exception.Message) }
if($errors.Count -gt 0){ foreach($e in $errors){ $line=((Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' PREFLIGHT ERROR: '+$e); Add-Content -LiteralPath $log -Value $line -Encoding UTF8; Write-Host $line -ForegroundColor Red }; Write-Host ('YUMRAM preflight found {0} error(s).' -f $errors.Count) -ForegroundColor Yellow; exit 2 }
Add-Content -LiteralPath $log -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' PREFLIGHT PASS: PowerShell, XAML, and config validation passed.') -Encoding UTF8
exit 0
