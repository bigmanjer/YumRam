#requires -Version 5.1
<#
Plain-language process guide (5.5). Used by the Top Processes window to explain, in everyday words,
what a running program is, whether it is safe to close, and what YUMRAM does with it.
Kinds: Windows, Security, Hardware, Game, App, Background, Unknown.
#>

$script:YumProcessGuide=@{
    'memory compression'=@('Memory Compression','Windows squeezes memory that programs are not using right now into a smaller space, so more fits in your RAM. A big number here is normal and is actually saving you memory.','Windows')
    'system'=@('Windows (System)','The core of Windows itself. Your PC cannot run without it.','Windows')
    'registry'=@('Windows Registry','Holds Windows'' settings in memory so they load fast.','Windows')
    'smss'=@('Windows Session Manager','Starts Windows when you turn the PC on.','Windows')
    'csrss'=@('Windows Client Server Runtime','A core part of Windows that manages windows and the console.','Windows')
    'wininit'=@('Windows Start-Up','Starts the Windows background services when the PC boots.','Windows')
    'winlogon'=@('Windows Sign-in','Handles signing in, locking and signing out.','Windows')
    'services'=@('Windows Services Manager','Starts and stops the Windows background services.','Windows')
    'lsass'=@('Windows Security Authority','Checks passwords and keeps you signed in securely.','Windows')
    'svchost'=@('Windows Service Host','Runs many small Windows services (network, audio, updates and more). Having dozens of these is normal.','Windows')
    'dwm'=@('Desktop Window Manager','Draws everything you see on the screen: windows, transparency and animations.','Windows')
    'explorer'=@('Windows Explorer','Your taskbar, Start button, desktop and File Explorer windows. Closing it makes the taskbar disappear until it restarts.','Windows')
    'searchhost'=@('Windows Search','The search box on the taskbar and in the Start menu.','Windows')
    'searchapp'=@('Windows Search','The search box on the taskbar and in the Start menu.','Windows')
    'searchindexer'=@('Windows Search Indexer','Keeps a list of your files so searching is fast.','Windows')
    'startmenuexperiencehost'=@('Start Menu','The Windows Start menu.','Windows')
    'shellexperiencehost'=@('Windows Shell','Notifications, the clock and calendar pop-up, and other taskbar panels.','Windows')
    'runtimebroker'=@('Runtime Broker','Checks that Store apps only use the permissions you gave them (camera, location...).','Windows')
    'sihost'=@('Shell Infrastructure Host','Helps the Start menu, taskbar and notifications work.','Windows')
    'taskhostw'=@('Windows Task Host','Runs small Windows tasks in the background.','Windows')
    'ctfmon'=@('Keyboard and Text Input','Handles typing, keyboard languages and the emoji panel.','Windows')
    'textinputhost'=@('Touch Keyboard and Emoji Panel','The on-screen keyboard and emoji picker.','Windows')
    'fontdrvhost'=@('Windows Font Driver','Draws the letters and fonts on your screen.','Windows')
    'audiodg'=@('Windows Audio','Processes all the sound your PC plays.','Windows')
    'spoolsv'=@('Print Spooler','Sends documents to your printer.','Windows')
    'wmiprvse'=@('WMI Provider Host','Answers questions programs ask about your PC (like YUMRAM asking how much RAM is free).','Windows')
    'dllhost'=@('COM Surrogate','A helper Windows uses to run small parts of programs safely, for example making thumbnails.','Windows')
    'conhost'=@('Console Window Host','Runs a text/command window for another program.','Windows')
    'sppsvc'=@('Windows Licensing','Software Protection: checks that Windows is activated.','Windows')
    'widgets'=@('Windows Widgets','The news, weather and widgets board.','Windows')
    'widgetservice'=@('Windows Widgets','The news, weather and widgets board.','Windows')
    'phoneexperiencehost'=@('Phone Link','Connects your phone to the PC for messages and notifications.','Background')
    'msmpeng'=@('Microsoft Defender Antivirus','Your antivirus. It scans files to keep your PC safe.','Security')
    'mpdefendercoreservice'=@('Microsoft Defender Core Service','Part of your antivirus protection.','Security')
    'nissrv'=@('Defender Network Protection','Part of Microsoft Defender that checks network traffic for attacks.','Security')
    'securityhealthservice'=@('Windows Security','The Windows Security center service.','Security')
    'securityhealthsystray'=@('Windows Security Icon','The shield icon for Windows Security in the notification area.','Security')
    'smartscreen'=@('SmartScreen','Warns you about dangerous downloads and websites.','Security')
    'vmmem'=@('Virtual Machine Memory','Memory used by a virtual machine or WSL (Linux on Windows).','Windows')
    'vmmemwsl'=@('WSL Memory','Memory used by Linux running inside Windows (WSL).','Windows')
    'onedrive'=@('OneDrive','Keeps your files synced with Microsoft''s cloud storage.','Background')
    'msedge'=@('Microsoft Edge','The Microsoft Edge web browser. Each tab and extension shows up as its own process.','App')
    'msedgewebview2'=@('Edge WebView2','Lets other apps show web pages inside their own windows (many apps use it).','Background')
    'chrome'=@('Google Chrome','The Chrome web browser. Each tab and extension is its own process, so it often uses a lot of RAM.','App')
    'firefox'=@('Mozilla Firefox','The Firefox web browser.','App')
    'opera'=@('Opera','The Opera web browser.','App')
    'opera_gx'=@('Opera GX','The Opera GX gaming web browser.','App')
    'brave'=@('Brave','The Brave web browser.','App')
    'discord'=@('Discord','Voice and text chat. Keeps running in the background so you get messages.','App')
    'steam'=@('Steam','The Steam game store and launcher.','App')
    'steamwebhelper'=@('Steam Web Helper','Steam''s built-in browser: the store, friends list and in-game overlay.','Background')
    'epicgameslauncher'=@('Epic Games Launcher','The Epic Games store and launcher.','App')
    'battle.net'=@('Battle.net','Blizzard''s game launcher.','App')
    'eadesktop'=@('EA app','EA''s game launcher.','App')
    'ms-teams'=@('Microsoft Teams','Chat and video calls for work or school.','App')
    'teams'=@('Microsoft Teams','Chat and video calls for work or school.','App')
    'spotify'=@('Spotify','Music streaming.','App')
    'slack'=@('Slack','Work chat.','App')
    'zoom'=@('Zoom','Video calls.','App')
    'code'=@('Visual Studio Code','A code editor.','App')
    'powershell'=@('Windows PowerShell','A command window. YUMRAM itself runs inside PowerShell, so one of these is YUMRAM.','App')
    'pwsh'=@('PowerShell 7','A command window.','App')
    'windowsterminal'=@('Windows Terminal','The window that hosts command prompts and PowerShell.','App')
    'claude'=@('Claude','The Claude desktop app.','App')
    'nvcontainer'=@('NVIDIA Container','Helper for your NVIDIA graphics card software (drivers, overlay, settings).','Hardware')
    'nvdisplay.container'=@('NVIDIA Display Driver Helper','Part of your NVIDIA graphics driver.','Hardware')
    'nvidia share'=@('NVIDIA Overlay','The NVIDIA in-game overlay (recording, screenshots).','Hardware')
    'nvidia app'=@('NVIDIA App','NVIDIA''s settings and driver update app.','Hardware')
    'amdrsserv'=@('AMD Radeon Software','Helper for your AMD graphics card software.','Hardware')
    'amdrssrcext'=@('AMD Radeon Software','Helper for your AMD graphics card software.','Hardware')
    'radeonsoftware'=@('AMD Radeon Software','Settings for your AMD graphics card.','Hardware')
    'atieclxx'=@('AMD Graphics Driver Helper','Part of your AMD graphics driver.','Hardware')
    'lghub'=@('Logitech G HUB','Settings for Logitech mice, keyboards and headsets.','Hardware')
    'lghub_agent'=@('Logitech G HUB Agent','Keeps your Logitech device settings working in the background.','Hardware')
    'lghub_system_tray'=@('Logitech G HUB Tray Icon','The G HUB icon in the notification area.','Hardware')
    'icue'=@('Corsair iCUE','Lighting and settings for Corsair devices.','Hardware')
    'razer synapse'=@('Razer Synapse','Settings for Razer devices.','Hardware')
    'armourycrate.service'=@('ASUS Armoury Crate','ASUS hardware control (fans, lighting, drivers).','Hardware')
    'armourycrate.usersessionhelper'=@('ASUS Armoury Crate Helper','Part of ASUS Armoury Crate.','Hardware')
    'asus_framework'=@('ASUS Framework','Part of ASUS hardware software.','Hardware')
    'rtkauduservice64'=@('Realtek Audio','Your sound card''s software.','Hardware')
    'msiafterburner'=@('MSI Afterburner','Graphics card tuning and FPS overlay.','Hardware')
    'overwolf'=@('Overwolf','A platform for in-game overlays and gaming apps.','Background')
}

function Get-YumProcessKind {
    # Best plain-language kind for a running program.
    param([string]$Name,[string]$Path,[string]$Company,[bool]$HasWindow,[bool]$IsGame,$Record)
    $key=([string]$Name).ToLowerInvariant()
    if($IsGame){return 'Game'}
    if($script:YumProcessGuide.ContainsKey($key)){return [string]$script:YumProcessGuide[$key][2]}
    if($null -ne $Record){
        $cat=''
        try{$cat=[string]$Record.Category}catch{}
        if($cat -match '(?i)game'){return 'Game'}
        if($cat -match '(?i)security'){return 'Security'}
        if($cat -match '(?i)driver|hardware'){return 'Hardware'}
        if($cat -match '(?i)windows system|protected'){return 'Windows'}
    }
    if($Path -match '(?i)^[a-z]:\\windows\\'){return 'Windows'}
    if([string]::IsNullOrWhiteSpace($Path) -and [string]::IsNullOrWhiteSpace($Company)){return 'Unknown'}
    if($HasWindow){return 'App'}
    return 'Background'
}

function Get-YumProcessExplanation {
    # Returns plain-language text blocks for the "What is this?" panel.
    param([string]$Name,[string]$Description,[string]$Company,[string]$Path,[string]$Kind,[bool]$Protected,[double]$MemoryMB,[int]$Count=1,[double]$TotalRamGB=0,$Record)
    $key=([string]$Name).ToLowerInvariant()
    $guide=if($script:YumProcessGuide.ContainsKey($key)){$script:YumProcessGuide[$key]}else{$null}
    $title=if($null -ne $guide){[string]$guide[0]}elseif(-not [string]::IsNullOrWhiteSpace($Description)){$Description}else{$Name}
    $what=if($null -ne $guide){[string]$guide[1]}else{
        switch($Kind){
            'Windows'    {'This is part of Windows itself.'}
            'Security'   {'This is part of your antivirus or security protection.'}
            'Hardware'   {'This is software for your hardware: graphics card, sound, mouse, keyboard or lighting.'}
            'Game'       {'A game that is running right now.'}
            'App'        {'A program you have open.'}
            'Background' {'A program running in the background without a window. It is often a helper for another app, an updater, or something that starts with Windows.'}
            default      {'YUMRAM could not identify this yet. Open the Intelligence Center and run a scan to research it.'}
        }
    }
    if($null -eq $guide -and -not [string]::IsNullOrWhiteSpace($Company)){$what+=(' Made by {0}.' -f $Company)}
    if($null -ne $Record){
        try{$r=[string]$Record.ResearchReason;if($Kind -eq 'Unknown' -and -not [string]::IsNullOrWhiteSpace($r)){$what+=(' Intelligence notes: {0}' -f ($r -split ';')[0])}}catch{}
    }
    $safe=switch($Kind){
        'Windows'    {'No. Windows needs it. Closing it can freeze or restart your PC.'}
        'Security'   {'No. It keeps your PC protected.'}
        'Hardware'   {'Better to leave it. Your device''s extra features (lighting, buttons, overlays) may stop until you restart.'}
        'Game'       {'Close it from inside the game so your progress is saved.'}
        'App'        {'Yes, if you are not using it. Close it normally and save your work first.'}
        'Background' {'Usually yes, but the app it belongs to may stop working properly until it is started again.'}
        default      {'Only if you know what it is.'}
    }
    $yum=if($Protected){'YUMRAM never touches it (protected).'}else{'When RAM runs low, YUMRAM may ask Windows to move the memory it is not using out of RAM. The program keeps running normally.'}
    $size=if($MemoryMB -ge 1024){'{0:N1} GB' -f ($MemoryMB/1024)}else{'{0:N0} MB' -f $MemoryMB}
    $amount=if($MemoryMB -ge 1024){'That is a lot.'}elseif($MemoryMB -ge 300){'That is a moderate amount.'}else{'That is a small amount.'}
    $share=if($TotalRamGB -gt 0){(' ({0:N1}% of your {1:N0} GB)' -f (($MemoryMB/1024)/$TotalRamGB*100),$TotalRamGB)}else{''}
    $parts=if($Count -gt 1){(' across {0} processes' -f $Count)}else{''}
    $memory=('Using {0}{1}{2}. {3}' -f $size,$share,$parts,$amount)
    if($key -eq 'memory compression'){$memory=('Holding {0} of compressed memory{1}. This is Windows saving space, not a problem.' -f $size,$share)}
    [pscustomobject]@{Title=$title;What=$what;Safe=$safe;Yumram=$yum;Memory=$memory}
}
