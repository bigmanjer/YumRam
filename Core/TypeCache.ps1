#requires -Version 5.1
# 5.15.9 (start-up measured): every start compiled the same ~12 C# helpers with Add-Type, and each compile starts
# the C# compiler (220-430 ms each on the test PC) - about 3 s of every start. Each helper is now compiled once into
# a DLL in YUMRAM's own Runtime\TypeCache folder (same folder trust as YUMRAM's scripts; never packaged) and loaded
# from there on later starts (~10-20 ms). The file name carries a hash of the source, references and runtime, so a
# changed helper (an update) is compiled again; anything unexpected falls back to the old in-memory compile.

function Get-YumTypeCacheDirectory {
    $base=Split-Path -Parent $PSScriptRoot
    return (Join-Path $base 'Runtime\TypeCache')
}

function Add-YumCompiledType {
    param(
        [Parameter(Mandatory=$true)][string]$TypeName,
        [Parameter(Mandatory=$true)][string]$Source,
        [string[]]$ReferencedAssemblies=@()
    )
    if($TypeName -as [type]){ return }
    $dll=$null
    try{
        $sha=[System.Security.Cryptography.SHA256]::Create()
        try{
            $text=$Source+'|'+(($ReferencedAssemblies | Sort-Object) -join ',')+'|'+[Environment]::Version.ToString()+'|'+[IntPtr]::Size
            $hash=(($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)) | Select-Object -First 8 | ForEach-Object { $_.ToString('x2') }) -join '')
        } finally { $sha.Dispose() }
        $dir=Get-YumTypeCacheDirectory
        $dll=Join-Path $dir ('{0}-{1}.dll' -f $TypeName,$hash)
        if([IO.File]::Exists($dll)){
            try{ [void][Reflection.Assembly]::LoadFrom($dll); if($TypeName -as [type]){ return } }catch{}
        }
        if(-not [IO.Directory]::Exists($dir)){ [void][IO.Directory]::CreateDirectory($dir) }
        $tmp=$dll+'.'+$PID+'.tmp'
        $p=@{TypeDefinition=$Source;OutputAssembly=$tmp;OutputType='Library';ErrorAction='Stop'}
        if(@($ReferencedAssemblies).Count){ $p.ReferencedAssemblies=$ReferencedAssemblies }
        Add-Type @p
        try{ if(-not [IO.File]::Exists($dll)){ [IO.File]::Move($tmp,$dll) } }catch{}
        try{ if([IO.File]::Exists($tmp)){ [IO.File]::Delete($tmp) } }catch{}
        if([IO.File]::Exists($dll)){
            [void][Reflection.Assembly]::LoadFrom($dll)
            # Older builds of this helper are no longer needed (a running older YUMRAM may still hold one; skipped).
            foreach($old in @([IO.Directory]::GetFiles($dir,($TypeName+'-*.dll')))){ if($old -ne $dll){ try{ [IO.File]::Delete($old) }catch{} } }
            if($TypeName -as [type]){ return }
        }
    }catch{}
    # Fallback: the original in-memory compile.
    if($TypeName -as [type]){ return }
    if(@($ReferencedAssemblies).Count){ Add-Type -TypeDefinition $Source -ReferencedAssemblies $ReferencedAssemblies }
    else{ Add-Type -TypeDefinition $Source }
}
