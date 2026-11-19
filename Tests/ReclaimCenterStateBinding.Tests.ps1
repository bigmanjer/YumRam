$ErrorActionPreference='Stop'
$root = Split-Path -Parent $PSScriptRoot
$dialogs = Get-Content (Join-Path $root 'UI\Dialogs.ps1') -Raw
if($dialogs.Contains('$state.FreeRam.Add_Click({param($s,$e)& $run $s.Tag')){throw 'Broken reclaim button state binding still uses Button.Tag.'}
# 5.2.x regex expected "'Quick')" but the handler is "'Quick'})"; use literal checks.
if(-not $dialogs.Contains('$state.FreeRam.Add_Click({param($s,$e)& $run $reclaimState ''Quick''})')){throw 'FREE RAM NOW does not bind to reclaim state.'}
if(-not $dialogs.Contains('$state.DeepReclaim.Add_Click({param($s,$e)& $run $reclaimState ''Deep''})')){throw 'DEEP RAM RECLAIM does not bind to reclaim state.'}
if(-not $dialogs.Contains('$state.Close.Add_Click({param($s,$e)$window.Close()})')){throw 'Close handler does not use the owning window.'}
'PASS - Reclaim Center state binding'
