$ErrorActionPreference='Stop'
$root = Split-Path -Parent $PSScriptRoot
$dialogs = Get-Content (Join-Path $root 'UI\Dialogs.ps1') -Raw
if($dialogs -match '\$state\.FreeRam\.Add_Click\(\{param\(\$s,\$e\)&\s+\$run\s+\$s\.Tag'){
    throw 'Broken reclaim button state binding still uses Button.Tag.'
}
if($dialogs -notmatch '\$state\.FreeRam\.Add_Click\(\{param\(\$s,\$e\)&\s+\$run\s+\$reclaimState\s+\x27Quick\x27\)'){
    throw 'FREE RAM NOW does not bind to reclaim state.'
}
if($dialogs -notmatch '\$state\.DeepReclaim\.Add_Click\(\{param\(\$s,\$e\)&\s+\$run\s+\$reclaimState\s+\x27Deep\x27\)'){
    throw 'DEEP RAM RECLAIM does not bind to reclaim state.'
}
if($dialogs -notmatch '\$state\.Close\.Add_Click\(\{param\(\$s,\$e\)\$window\.Close\(\)\}'){
    throw 'Close handler does not use the owning window.'
}
'PASS — Reclaim Center state binding'
