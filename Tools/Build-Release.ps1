#requires -Version 5.1
<#
Builds a GitHub release package in dist\:
  YUMRAM-<version>.zip   program files + YUMRAM.exe (no user data, no tests, no screenshots)
  SHA256SUMS.txt         "<sha256>  YUMRAM-<version>.zip" - YUMRAM refuses to install an update without it
Upload both to a GitHub Release whose tag is v<version>. GitHub also publishes its own SHA-256 "digest"
for every asset; YUMRAM's updater prefers that and falls back to SHA256SUMS.txt.

  powershell -NoProfile -ExecutionPolicy Bypass -File Tools\Build-Release.ps1
  -Version 9.9.9 -OutDir <dir>   (tests: build a package with another version number)
#>
param([string]$Version,[string]$OutDir,[switch]$AsInvoker)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if(-not $Version){$Version=([IO.File]::ReadAllText((Join-Path $root 'VERSION'))).Trim()}
if(-not $OutDir){$OutDir=Join-Path $root 'dist'}
$stage=Join-Path $env:TEMP ('yumram-release-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
try{
    # Program files only. User data (config.json, statistics, learned data, logs) is never packaged.
    # 5.12: only what runs YUMRAM. Build scripts, launcher sources, tests and docs stay in the repository.
    $include=@('App','Config','Core','UI')
    foreach($d in $include){ Copy-Item -LiteralPath (Join-Path $root $d) -Destination (Join-Path $stage $d) -Recurse -Force }
    New-Item -ItemType Directory -Path (Join-Path $stage 'Launcher') -Force | Out-Null; Copy-Item -LiteralPath (Join-Path $root 'Launcher\YUMRAM.ico') -Destination (Join-Path $stage 'Launcher')
    foreach($f in 'README.md','CHANGELOG.md'){ $src=Join-Path $root $f; if(Test-Path -LiteralPath $src){Copy-Item -LiteralPath $src -Destination $stage} }
    [IO.File]::WriteAllText((Join-Path $stage 'VERSION'),$Version+"`r`n")
    $cfg=Join-Path $stage 'Config\default-config.json'
    $json=[IO.File]::ReadAllText($cfg)
    $json=[regex]::Replace($json,'"Version":\s*"[^"]*"',('"Version": "{0}"' -f $Version))
    $json=[regex]::Replace($json,'"ResearchEngineVersion":\s*"[^"]*"',('"ResearchEngineVersion": "{0}"' -f $Version))
    [IO.File]::WriteAllText($cfg,$json,(New-Object Text.UTF8Encoding($false)))
    $build=Join-Path $PSScriptRoot 'Build-Launcher.ps1'
    $buildArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$build,'-Out',(Join-Path $stage 'YUMRAM.exe'));if($AsInvoker){$buildArgs+='-AsInvoker'}
    & powershell.exe @buildArgs
    if($LASTEXITCODE -ne 0){throw 'Building YUMRAM.exe failed.'}
    $zip=Join-Path $OutDir ('YUMRAM-{0}.zip' -f $Version)
    if(Test-Path -LiteralPath $zip){Remove-Item -LiteralPath $zip -Force}
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    # 5.12.1: entry names with "/" (the ZIP standard). ZipFile.CreateFromDirectory in Windows PowerShell
    # writes "App\YUMRAM.ps1", which 7-Zip warns about and macOS/Linux unpack as flat file names.
    Add-Type -AssemblyName System.IO.Compression
    $fs=[IO.File]::Open($zip,[IO.FileMode]::CreateNew)
    try{
        $za=New-Object IO.Compression.ZipArchive($fs,[IO.Compression.ZipArchiveMode]::Create)
        try{
            foreach($file in (Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object FullName)){
                $name=$file.FullName.Substring($stage.Length).TrimStart('\').Replace('\','/')
                $entry=$za.CreateEntry($name,[IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime=$file.LastWriteTime
                $es=$entry.Open();$in=[IO.File]::OpenRead($file.FullName)
                try{$in.CopyTo($es)}finally{$in.Dispose();$es.Dispose()}
            }
        }finally{$za.Dispose()}
    }finally{$fs.Dispose()}
    # 5.12: YUMRAM-Setup-<version>.exe - per-user installer with the zip embedded (Launcher\YumramSetup.cs).
    $setupExe=Join-Path $OutDir ('YUMRAM-Setup-{0}.exe' -f $Version)
    $csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    $refs=@('System.Windows.Forms.dll','System.Drawing.dll','System.IO.Compression.dll','System.IO.Compression.FileSystem.dll','Microsoft.CSharp.dll','System.Core.dll') | ForEach-Object { '/reference:'+$_ }
    $setupArgs=@('/nologo','/target:winexe','/optimize+',('/out:"{0}"' -f $setupExe),('/win32icon:"{0}"' -f (Join-Path $root 'Launcher\YUMRAM.ico')),('/resource:"{0}",YUMRAM.zip' -f $zip))+$refs+@(('"{0}"' -f (Join-Path $root 'Launcher\YumramSetup.cs')))
    $setupOut=& $csc @setupArgs 2>&1
    if($LASTEXITCODE -ne 0){throw ("Building the installer failed:`n{0}" -f ($setupOut -join "`n"))}
    $setupHash=(Get-FileHash -LiteralPath $setupExe -Algorithm SHA256).Hash.ToLowerInvariant()
    $hash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText((Join-Path $OutDir 'SHA256SUMS.txt'),(('{0}  {1}' -f $hash,[IO.Path]::GetFileName($zip))+"`n"+('{0}  {1}' -f $setupHash,[IO.Path]::GetFileName($setupExe))+"`n"))
    Write-Host ('Installer: {0} ({1:N0} KB)' -f $setupExe,((Get-Item $setupExe).Length/1KB))
    Write-Host ('Release package: {0} ({1:N0} KB)' -f $zip,((Get-Item $zip).Length/1KB))
    Write-Host ('SHA-256: {0}' -f $hash)
    Write-Host ('Next: create GitHub release tag v{0}, attach YUMRAM-Setup-{0}.exe, the zip and SHA256SUMS.txt.' -f $Version)
}finally{ Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
