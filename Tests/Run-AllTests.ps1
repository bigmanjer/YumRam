#requires -Version 5.1
<#
Runs every YUMRAM test in its own Windows PowerShell 5.1 process (tests dot-source modules and
set $script: state, so they must not share a session). Restores config.json afterwards because
some tests call Initialize-YumConfig, which rewrites it.

Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File Tests\Run-AllTests.ps1
Exit code 0 = all passed.
#>
param([int]$TimeoutSeconds=120)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$config=Join-Path $root 'config.json'
$configBackup=$null
if(Test-Path -LiteralPath $config){$configBackup=[IO.File]::ReadAllBytes($config)}
$results=New-Object System.Collections.Generic.List[object]
try {
    foreach($test in Get-ChildItem -LiteralPath $PSScriptRoot -Filter *.ps1 | Where-Object { $_.Name -ne 'Run-AllTests.ps1' } | Sort-Object Name){
        $out=[IO.Path]::GetTempFileName();$err=[IO.Path]::GetTempFileName()
        $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $test.FullName))
        if($test.Name -eq 'Preflight.ps1'){$args+=@('-Root',('"{0}"' -f $root))}
        $sw=[Diagnostics.Stopwatch]::StartNew()
        $p=Start-Process powershell.exe -ArgumentList $args -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -WindowStyle Hidden
        $null=$p.Handle  # cache the handle now, or ExitCode is null after a timed WaitForExit
        if(-not $p.WaitForExit($TimeoutSeconds*1000)){try{$p.Kill()}catch{};$code='TIMEOUT'}else{$code=$p.ExitCode}
        # Windows PowerShell writes progress records to stderr as CLIXML even on success; keep only real error text.
        $stderr=[IO.File]::ReadAllText($err).Trim()
        if($stderr.StartsWith('#< CLIXML')){
            $stderr=(([regex]::Matches($stderr,'<S S="Error">(.*?)</S>') | ForEach-Object { $_.Groups[1].Value -replace '_x000D__x000A_',' ' }) -join ' ').Trim()
        }
        $stdout=[IO.File]::ReadAllText($out).Trim()
        Remove-Item -LiteralPath $out,$err -Force -ErrorAction SilentlyContinue
        $passed=($code -eq 0 -and [string]::IsNullOrWhiteSpace($stderr))
        $detail=if($passed){($stdout -split "`r?`n")[-1]}else{(($stderr,$stdout) -join ' ') -replace '\s+',' '}
        $results.Add([pscustomobject]@{Result=if($passed){'PASS'}else{'FAIL'};Test=$test.BaseName;Seconds=[math]::Round($sw.Elapsed.TotalSeconds,1);Detail=$detail.Substring(0,[math]::Min(160,$detail.Length))})
    }
} finally {
    if($null -ne $configBackup){[IO.File]::WriteAllBytes($config,$configBackup)}
    foreach($junk in 'research-live-results.json','research-live-results.tmp','Tests\tmp-intelligence-db.json'){Remove-Item -LiteralPath (Join-Path $root $junk) -Force -ErrorAction SilentlyContinue}
}
$results | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Write-Host
$failed=@($results | Where-Object Result -eq 'FAIL').Count
Write-Host ('{0} passed, {1} failed, {2} total.' -f ($results.Count-$failed),$failed,$results.Count)
exit $(if($failed -eq 0){0}else{1})
