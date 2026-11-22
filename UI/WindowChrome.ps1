#requires -Version 5.1
if(-not (Get-Command Add-YumCompiledType -ErrorAction SilentlyContinue)){ . (Join-Path $PSScriptRoot '..\Core\TypeCache.ps1') }
# 5.16.2 (user: "make it not look like a PowerShell program - the top bar and the taskbar"). YUMRAM runs inside
# powershell.exe, so Windows showed PowerShell's icon in the title bar and on the taskbar, grouped it with PowerShell
# and pinned PowerShell. Now: YUMRAM's own icon on every window, its own taskbar identity (AppUserModelID; pinning
# starts YUMRAM.exe), and a dark title bar in YUMRAM's colours (Windows 11; Windows 10 gets the dark title bar).

if(-not ('YumWindowChrome' -as [type])){
    Add-YumCompiledType -TypeName 'YumWindowChrome' -Source @'
using System; using System.Runtime.InteropServices;
public static class YumWindowChrome {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
    [DllImport("shell32.dll")] static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out IPropertyStore store);
    [DllImport("ole32.dll")] static extern int PropVariantClear(ref PROPVARIANT pv);

    [StructLayout(LayoutKind.Sequential, Pack = 4)] struct PROPERTYKEY { public Guid fmtid; public uint pid; public PROPERTYKEY(Guid g, uint p) { fmtid = g; pid = p; } }
    [StructLayout(LayoutKind.Explicit)] struct PROPVARIANT { [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public IntPtr p; [FieldOffset(16)] public IntPtr pad; }
    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore {
        int GetCount(out uint count);
        int GetAt(uint index, out PROPERTYKEY key);
        int GetValue(ref PROPERTYKEY key, out PROPVARIANT pv);
        int SetValue(ref PROPERTYKEY key, ref PROPVARIANT pv);
        int Commit();
    }
    static readonly Guid AppModel = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");

    // Taskbar identity of the whole process (call before the first window shows).
    public static bool SetProcessAppId(string appId) { try { return SetCurrentProcessExplicitAppUserModelID(appId) == 0; } catch { return false; } }

    // Taskbar identity of one window + what "pin to taskbar" starts and shows.
    public static bool SetWindowIdentity(IntPtr hwnd, string appId, string relaunchCommand, string displayName, string iconResource) {
        IPropertyStore store = null;
        try {
            Guid iid = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
            if (SHGetPropertyStoreForWindow(hwnd, ref iid, out store) != 0 || store == null) return false;
            Set(store, 5, appId);
            if (!String.IsNullOrEmpty(relaunchCommand)) {
                Set(store, 2, relaunchCommand);
                Set(store, 4, displayName);
                if (!String.IsNullOrEmpty(iconResource)) Set(store, 3, iconResource);
            }
            store.Commit();
            return true;
        } catch { return false; }
        finally { if (store != null) Marshal.ReleaseComObject(store); }
    }
    static void Set(IPropertyStore store, uint pid, string value) {
        var key = new PROPERTYKEY(AppModel, pid);
        var pv = new PROPVARIANT(); pv.vt = 31; pv.p = Marshal.StringToCoTaskMemUni(value ?? "");
        try { store.SetValue(ref key, ref pv); } finally { PropVariantClear(ref pv); }
    }

    // Dark title bar; on Windows 11 also YUMRAM's caption, text and border colours (COLORREF 0x00BBGGRR).
    public static void SetCaption(IntPtr hwnd, int caption, int text, int border) {
        int on = 1;
        try { if (DwmSetWindowAttribute(hwnd, 20, ref on, 4) != 0) DwmSetWindowAttribute(hwnd, 19, ref on, 4); } catch { }
        try { DwmSetWindowAttribute(hwnd, 35, ref caption, 4); } catch { }
        try { DwmSetWindowAttribute(hwnd, 36, ref text, 4); } catch { }
        try { DwmSetWindowAttribute(hwnd, 34, ref border, 4); } catch { }
    }
}
'@
}

$script:YumAppId='YUMRAM.App'
$script:YumWindowIcon=$null

function Get-YumColorRef([string]$Hex){
    $h=$Hex.TrimStart('#'); $r=[Convert]::ToInt32($h.Substring(0,2),16); $g=[Convert]::ToInt32($h.Substring(2,2),16); $b=[Convert]::ToInt32($h.Substring(4,2),16)
    return [int]($r -bor ($g -shl 8) -bor ($b -shl 16))
}

function Get-YumWindowIcon {
    if($null -ne $script:YumWindowIcon){ return $script:YumWindowIcon }
    try{
        $ico=Join-Path $script:Yum.Root 'Launcher\YUMRAM.ico'
        if([IO.File]::Exists($ico)){
            $dec=New-Object System.Windows.Media.Imaging.IconBitmapDecoder((New-Object Uri($ico)),[System.Windows.Media.Imaging.BitmapCreateOptions]::None,[System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
            # The largest frame; Windows scales it for the title bar and taskbar.
            $script:YumWindowIcon=@($dec.Frames | Sort-Object PixelWidth -Descending)[0]
        }
    }catch{}
    return $script:YumWindowIcon
}

function Set-YumProcessIdentity {
    # Before the first window: the taskbar groups YUMRAM's windows as "YUMRAM", not with PowerShell.
    try{ [void][YumWindowChrome]::SetProcessAppId($script:YumAppId) }catch{}
}

function Set-YumWindowLook {
    # Icon + dark title bar for any YUMRAM window; -Main also sets the taskbar relaunch details (pin = YUMRAM.exe).
    param([System.Windows.Window]$Window,[switch]$Main)
    if($null -eq $Window){return}
    try{ $i=Get-YumWindowIcon; if($null -ne $i -and $null -eq $Window.Icon){ $Window.Icon=$i } }catch{}
    try{
        $hwnd=(New-Object System.Windows.Interop.WindowInteropHelper($Window)).Handle
        if($hwnd -eq [IntPtr]::Zero){return}
        [YumWindowChrome]::SetCaption($hwnd,(Get-YumColorRef '#1B1224'),(Get-YumColorRef '#F4EEFB'),(Get-YumColorRef '#A855F7'))
        if($Main){
            $exe=Join-Path $script:Yum.Root 'YUMRAM.exe'
            $cmd=if([IO.File]::Exists($exe)){'"'+$exe+'"'}else{''}
            [void][YumWindowChrome]::SetWindowIdentity($hwnd,$script:YumAppId,$cmd,'YUMRAM',$(if($cmd){$exe+',0'}else{''}))
        }
    }catch{}
}

function Register-YumWindowLook {
    # Every YUMRAM window (dialogs too) gets the look as soon as it has a handle.
    if([bool]$script:Yum['WindowLookRegistered']){return}
    try{
        [System.Windows.EventManager]::RegisterClassHandler([System.Windows.Window],[System.Windows.FrameworkElement]::LoadedEvent,[System.Windows.RoutedEventHandler]{ param($s,$e) try{ if(-not [object]::ReferenceEquals($s,$script:Yum.Window)){ Set-YumWindowLook -Window $s } }catch{} })
        $script:Yum['WindowLookRegistered']=$true
    }catch{}
}
