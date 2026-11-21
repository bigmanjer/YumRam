#requires -Version 5.1
# 5.15.2 (user report: a friend "didn't know what things were for - it told him what it was, but not for what
# device or stuff like that"). One plain answer to "what is it for?" used by Intelligence, What's running and
# Startup apps. Sources, best first: YUMRAM's catalog, the Windows service description, the file's own
# description / product name, then a device guess from all of that text. Read-only and cached.

$script:YumPurposeCache=@{}
$script:YumServiceDescriptions=$null

# Device / feature words -> what it is for. First match wins, so specific entries come first.
$script:YumPurposeDevices=@(
    @{M='(?i)ui\.xaml|net\.native|vclibs|windowsappruntime|\.framework|\bruntime\b|redistributable|visual c\+\+|\.net (desktop )?runtime|webview2 runtime';U='other apps need it to run (a shared building block - keep it)'}
    @{M='(?i)touch ?pad|precision ?touch|\bptp\b|synaptics|elan(tech)?\b|smartpad';U='your touchpad (gestures, scrolling)'}
    @{M='(?i)finger ?print|biometric|windows hello|face ?auth|goodix|egis';U='fingerprint or face sign-in (Windows Hello)'}
    @{M='(?i)web ?cam|camera|\bcam\b|realsense';U='your camera'}
    @{M='(?i)bluetooth|\bbth';U='Bluetooth (wireless headphones, mice, controllers, phones)'}
    @{M='(?i)wi-?fi|wireless lan|\bwlan|killer|intel.*(proset|wireless)';U='Wi-Fi'}
    @{M='(?i)ethernet|network adapter|realtek.*(pcie|gbe|network)';U='the wired network (Ethernet)'}
    @{M='(?i)voicemeeter|vb-audio|virtual (audio )?cable';U='routing your microphone and speakers (virtual audio mixer)'}
    @{M='(?i)audio|sound|speaker|microphone|\bmic\b|realtek hd|rtkaud|dolby|\bdts\b|nahimic|waves maxx|sonic studio|conexant|smart ?amp|sound ?blaster|asio';U='sound: your speakers, headphones and microphone'}
    @{M='(?i)headset|arctis|hyperx ngenuity|steelseries gg|\bsonar\b';U='your headset'}
    @{M='(?i)printer|print spooler|\bspool|\bprint\b|scanner|hp smart|epson|canon|brother|twain|\bwia\b';U='printers and scanners'}
    @{M='(?i)xbox (controller|wireless)|dualsense|dualshock|ds4windows|steam ?input|game ?controller|gamepad|\bxinput\b|vigem';U='game controllers'}
    @{M='(?i)hotkey|\bfn\b|\bosd\b|on-screen display|atkosd|function key';U='the Fn keys (volume, brightness, keyboard light)'}
    @{M='(?i)\brgb\b|aura|lighting|\bchroma\b|icue|mystic light|polychrome|signalrgb|openrgb';U='RGB lighting (keyboard, case, mouse lights)'}
    @{M='(?i)logitech|g ?hub|lghub|razer synapse|razer central|corsair|steelseries|roccat|mouse|keyboard';U='your mouse, keyboard or headset (buttons, DPI, lights)'}
    @{M='(?i)\bfan\b|thermal|cooling|armoury|omen|alienware command|dragon center|msi center|legion|vantage|predatorsense|nitrosense';U='fans, performance modes and battery care (your laptop maker''s control app)'}
    @{M='(?i)battery|power manag|\bacpi\b|charging';U='battery and power'}
    @{M='(?i)nvidia|geforce|radeon|\bamd\b.*(software|adrenalin|display|graphics|noise)|\batiedx|intel.*graphics|\bigfx|arc control|\bgpu\b|graphics';U='your graphics card (games, video, screens)'}
    @{M='(?i)display (driver|settings|control)|refresh ?rate|splendid|\bhdr\b|night light|colou?r profile|screen colou?r|brightness control';U='your screen (colours, brightness, refresh rate)'}
    @{M='(?i)\bssd\b|\bnvme\b|storage|samsung magician|crucial|rapid storage|\birst\b|optane|\braid\b';U='your SSD or hard drive'}
    @{M='(?i)\busb\b|thunderbolt|dock(ing)? station|displaylink';U='USB / Thunderbolt devices and docks'}
    @{M='(?i)phone link|your phone|android|iphone|itunes|apple mobile|appledevices|smart switch';U='connecting your phone'}
    @{M='(?i)onedrive|dropbox|google drive|icloud|megasync|sync ?center';U='syncing files to the cloud'}
    @{M='(?i)vanguard|\bvg(c|k|tray)\b|easy ?anti ?cheat|battleye|\beac\b|faceit|ricochet|anti-?cheat';U='anti-cheat for online games (the game will not start without it)'}
    @{M='(?i)defender|antivirus|anti-?malware|security|firewall|malwarebytes|norton|mcafee|avast|bitdefender|kaspersky|eset|smartscreen';U='protecting the PC from viruses and attacks'}
    @{M='(?i)steam|epic games|battle\.?net|ea app|origin|ubisoft|uplay|gog galaxy|riot client|gaming services|rockstar';U='a game store / launcher'}
    @{M='(?i)discord|teams|slack|zoom|skype|whatsapp|telegram';U='chat and calls'}
    @{M='(?i)\bobs\b|streamlabs|shadowplay|nvidia share|relive|medal|outplayed|game ?bar';U='recording or streaming your screen and games'}
    @{M='(?i)telemetry|analytics|diagnos|feedback|crash ?report|customer experience';U='sending usage or crash reports to the maker (optional)'}
    @{M='(?i)update|updater|installer';U='keeping a program up to date'}
    @{M='(?i)vpn|wireguard|openvpn|nordvpn|proton';U='a VPN connection'}
    @{M='(?i)chrome|edge|firefox|opera|brave|browser|webview';U='web browsing (or a web page inside another app)'}
    @{M='(?i)spotify|music|media player|vlc|netflix';U='music and video'}
)

function Get-YumServiceDescriptionMap {
    if($null -eq $script:YumServiceDescriptions){
        $m=@{}
        try{ foreach($s in @(Get-CimInstance Win32_Service -Property Name,DisplayName,Description,PathName -ErrorAction Stop -OperationTimeoutSec 5)){
                 $d=[string]$s.Description; if([string]::IsNullOrWhiteSpace($d) -or $d -match '^@'){continue}
                 $m[([string]$s.Name).ToLowerInvariant()]=$d; $m[([string]$s.DisplayName).ToLowerInvariant()]=$d
                 # By exe name too, except shared hosts (svchost runs dozens of services).
                 if($s.PathName -match '([^\\"]+)\.exe'){ $exe=$Matches[1].ToLowerInvariant(); if($exe -notin @('svchost','dllhost','rundll32','conhost') -and -not $m.ContainsKey('exe:'+$exe)){$m['exe:'+$exe]=$d} } } }catch{}
        $script:YumServiceDescriptions=$m
    }
    return $script:YumServiceDescriptions
}

function Get-YumFirstSentence {
    param([string]$Text,[int]$Max=180)
    $t=([string]$Text -replace '\s+',' ').Trim()
    if(-not $t){return ''}
    $i=$t.IndexOf('. '); if($i -gt 20){$t=$t.Substring(0,$i+1)}
    if($t.Length -gt $Max){$t=$t.Substring(0,$Max-1).TrimEnd()+'...'}
    return $t
}

function Get-YumPurpose {
    # Returns @{What=<what it does, one sentence>; UsedFor=<device or feature>; Product=<product (company)>; Text=<all of it, ready to show>}.
    param([string]$Name='',[string]$Path='',[string]$Publisher='',[string]$Description='',[string]$DisplayName='')
    $key=('{0}|{1}|{2}' -f $Name,$Path,$DisplayName).ToLowerInvariant()
    if($script:YumPurposeCache.ContainsKey($key)){return $script:YumPurposeCache[$key]}
    $what='';$product='';$company=$Publisher
    $known=$null; try{ $known=Get-YumKnownApp -Name $Name -Path $Path -Publisher $Publisher -DisplayName $DisplayName }catch{}
    if($null -ne $known -and $known.What){ $what=[string]$known.What }
    # Windows' own service description ("Provides support for ...") is usually the clearest sentence there is.
    $svc=''
    try{ $map=Get-YumServiceDescriptionMap; $n=([string]$Name -replace '\.exe$','').ToLowerInvariant()
         foreach($k in @($n,([string]$DisplayName).ToLowerInvariant(),('exe:'+$n))){ if($k -and $k -ne 'exe:' -and $map.ContainsKey($k)){ $svc=[string]$map[$k]; break } } }catch{}
    # The file's own description and product name.
    $file=''
    try{ $exe=[Environment]::ExpandEnvironmentVariables(([string]$Path).Trim())
         if($exe -match '^"?([^"]+?\.(exe|dll|sys))'){ $exe=$Matches[1] }
         if($exe -and $exe -match '\.(exe|dll|sys)$' -and (Test-Path -LiteralPath $exe -PathType Leaf)){
             $vi=[Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
             $file=([string]$vi.FileDescription).Trim(); $product=([string]$vi.ProductName).Trim(); if(-not $company){$company=([string]$vi.CompanyName).Trim()} } }catch{}
    if(-not $file -and $Description){ $file=$Description }
    if(-not $what){ $what=if($svc){Get-YumFirstSentence $svc}elseif($file -and $file -ne $Name){Get-YumFirstSentence $file}else{''} }
    $hay=('{0} {1} {2} {3} {4} {5} {6} {7}' -f $Name,$DisplayName,$Path,$Publisher,$file,$product,$svc,$(if($known){$known.Label}else{''}))
    $used=''; foreach($d in $script:YumPurposeDevices){ if($hay -match $d.M){ $used=[string]$d.U; break } }
    $prod=''
    if($product -and $product -notmatch '(?i)operating system|^windows$' -and $product -ne $Name -and $product -ne $what){ $prod=$product }
    if($company -and $company -notmatch '^(Unknown|Unsigned)'){ $prod=if($prod){('{0} by {1}' -f $prod,$company)}else{('made by {0}' -f $company)} }
    $prod=$prod.TrimEnd('.')
    $what=$what.Trim(); if($what -and $what -notmatch '[.!?]$'){$what+='.'}
    $parts=@()
    if($what){$parts+=$what}
    if($used){$parts+=('Used for: {0}.' -f $used)}
    if($prod){$parts+=('Part of: {0}.' -f $prod)}
    $text=if($parts.Count){$parts -join ' '}else{''}   # callers keep their own text when there is nothing to add
    $r=[pscustomobject]@{What=$what;UsedFor=$used;Product=$prod;Text=$text}
    $script:YumPurposeCache[$key]=$r
    return $r
}
