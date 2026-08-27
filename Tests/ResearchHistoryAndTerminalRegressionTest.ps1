$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$research=Join-Path $root 'Core\Research.ps1'
$text=Get-Content -LiteralPath $research -Raw
$checks=@()
$checks += [pscustomobject]@{Name='History reads Items container';Pass=($text -match "\$obj\.PSObject\.Properties\['Items'\]")}
$checks += [pscustomobject]@{Name='History excludes metadata recursion';Pass=($text -match "\[string\]\$prop -in @\('Version','Updated','Items'\)")}
$checks += [pscustomobject]@{Name='Completed nonterminal result quarantines';Pass=($text -match 'Research completed but corroboration remained insufficient')}
$checks += [pscustomobject]@{Name='Research Error is terminal';Pass=($text -match "ResearchComplete.*ResearchError|@\('Organized','Unknown','Research Error'\)")}
$failed=@($checks|Where-Object{-not $_.Pass})
$checks|ForEach-Object{if($_.Pass){Write-Host "PASS $($_.Name)"}else{Write-Host "FAIL $($_.Name)"}}
if($failed.Count){exit 1}
exit 0
