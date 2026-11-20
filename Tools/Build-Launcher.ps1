#requires -Version 5.1
<#
Builds YUMRAM.exe (Launcher\YumramLauncher.cs) with the C# compiler that ships with .NET Framework 4,
so no SDK or extra tools are needed. Also draws Launcher\YUMRAM.ico (PNG frames 16-256 px).

  powershell -NoProfile -ExecutionPolicy Bypass -File Tools\Build-Launcher.ps1
  -AsInvoker   build without the administrator manifest (used by tests so no UAC prompt appears)
  -Out <path>  where to write the exe (default: YUMRAM.exe in the YUMRAM folder)
#>
param([switch]$AsInvoker,[string]$Out)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if(-not $Out){$Out=Join-Path $root 'YUMRAM.exe'}
$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if(-not (Test-Path -LiteralPath $csc)){$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'}
if(-not (Test-Path -LiteralPath $csc)){throw 'The .NET Framework 4 C# compiler (csc.exe) was not found.'}

# --- Icon: purple rounded square with a white heart-ish "Y" mark, drawn at several sizes. ---
$ico=Join-Path $root 'Launcher\YUMRAM.ico'
Add-Type -AssemblyName System.Drawing
function New-YumIconPng([int]$Size){
    $bmp=New-Object System.Drawing.Bitmap($Size,$Size,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g=[System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode='AntiAlias';$g.TextRenderingHint='AntiAliasGridFit';$g.Clear([System.Drawing.Color]::Transparent)
    $r=[math]::Max(2,[int]($Size*0.22));$d=$r*2;$w=$Size-1
    $path=New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0,0,$d,$d,180,90);$path.AddArc($w-$d,0,$d,$d,270,90);$path.AddArc($w-$d,$w-$d,$d,$d,0,90);$path.AddArc(0,$w-$d,$d,$d,90,90);$path.CloseFigure()
    $brush=New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Point(0,0)),(New-Object System.Drawing.Point($Size,$Size)),[System.Drawing.Color]::FromArgb(255,168,85,247),[System.Drawing.Color]::FromArgb(255,236,72,153))
    $g.FillPath($brush,$path)
    $font=New-Object System.Drawing.Font('Segoe UI',[single]($Size*0.58),[System.Drawing.FontStyle]::Bold,[System.Drawing.GraphicsUnit]::Pixel)
    $sf=New-Object System.Drawing.StringFormat;$sf.Alignment='Center';$sf.LineAlignment='Center'
    $g.DrawString('Y',$font,[System.Drawing.Brushes]::White,(New-Object System.Drawing.RectangleF(0,[single]($Size*0.03),$Size,$Size)),$sf)
    $g.Dispose();$ms=New-Object System.IO.MemoryStream;$bmp.Save($ms,[System.Drawing.Imaging.ImageFormat]::Png);$bmp.Dispose()
    return ,$ms.ToArray()
}
$sizes=@(16,24,32,48,64,128,256);$pngs=@($sizes | ForEach-Object { ,(New-YumIconPng $_) })
$fs=[IO.File]::Create($ico);$bw=New-Object System.IO.BinaryWriter($fs)
try{
    $bw.Write([uint16]0);$bw.Write([uint16]1);$bw.Write([uint16]$sizes.Count)
    $offset=6+16*$sizes.Count
    for($i=0;$i -lt $sizes.Count;$i++){
        $s=$sizes[$i];$len=$pngs[$i].Length
        $bw.Write([byte]$(if($s -ge 256){0}else{$s}));$bw.Write([byte]$(if($s -ge 256){0}else{$s}));$bw.Write([byte]0);$bw.Write([byte]0)
        $bw.Write([uint16]1);$bw.Write([uint16]32);$bw.Write([uint32]$len);$bw.Write([uint32]$offset);$offset+=$len
    }
    foreach($p in $pngs){$bw.Write([byte[]]$p)}
}finally{$bw.Dispose()}

# --- Compile. ---
$src=Join-Path $root 'Launcher\YumramLauncher.cs'
$cscArgs=@('/nologo','/target:winexe','/optimize+','/platform:anycpu',('/out:"{0}"' -f $Out),('/win32icon:"{0}"' -f $ico),'/reference:System.Windows.Forms.dll','/reference:System.Management.dll')
if(-not $AsInvoker){$cscArgs+=('/win32manifest:"{0}"' -f (Join-Path $root 'Launcher\YUMRAM.manifest'))}
$cscArgs+=('"{0}"' -f $src)
$cscOut=& $csc @cscArgs 2>&1
if($LASTEXITCODE -ne 0){throw ("csc failed:`n{0}" -f ($cscOut -join "`n"))}
$h=(Get-FileHash -LiteralPath $Out -Algorithm SHA256).Hash
Write-Host ('Built {0} ({1:N0} KB, SHA-256 {2}){3}' -f $Out,((Get-Item $Out).Length/1KB),$h,$(if($AsInvoker){' [no admin manifest]'}else{''}))
