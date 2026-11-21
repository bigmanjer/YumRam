#requires -Version 5.1
# 5.15.2 (user request: "minimize to a little bar or box that can float and move on screen, and be able to hide it
# in the tray / the little arrow on the taskbar"). A small always-on-top bar with RAM, CPU, GPU and disk, Free RAM,
# Open and Hide (to the tray icon). Drag it anywhere; its position is remembered. Reads only while it is visible
# (every 2 s, ~20-40 ms measured for all four readings).

$script:YumMiniXaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="YUMRAM mini" WindowStyle="None" AllowsTransparency="True" Background="Transparent" ResizeMode="NoResize"
        Topmost="True" ShowInTaskbar="False" SizeToContent="WidthAndHeight" ShowActivated="False">
  <Border x:Name="Shell" Background="#F01A1024" BorderBrush="#5B3B7A" BorderThickness="1" CornerRadius="12" Padding="10,7" Cursor="SizeAll"
          ToolTip="YUMRAM mini bar. Drag to move. Double-click to open YUMRAM.">
    <StackPanel Orientation="Horizontal">
      <TextBlock Text="YUM" FontWeight="Bold" Foreground="#C084FC" VerticalAlignment="Center" Margin="0,0,10,0" FontSize="12"/>
      <StackPanel x:Name="Stats" Orientation="Horizontal" VerticalAlignment="Center"/>
      <Button x:Name="MiniFree" Content="Free RAM" Margin="10,0,0,0" Padding="9,3" FontSize="11.5" Cursor="Hand" ToolTip="Free RAM now (same as the main button)"/>
      <Button x:Name="MiniOpen" Content="Open" Margin="6,0,0,0" Padding="9,3" FontSize="11.5" Cursor="Hand" ToolTip="Open the full YUMRAM window"/>
      <Button x:Name="MiniHide" Content="–" Margin="6,0,0,0" Padding="8,1" FontSize="13" FontWeight="Bold" Cursor="Hand" ToolTip="Hide to the YUMRAM icon near the clock (it may be under the ^ arrow). Click the icon to bring YUMRAM back."/>
    </StackPanel>
  </Border>
</Window>
'@

function New-YumMiniStat {
    param([string]$Label,[string]$Hex)
    $sp=New-Object System.Windows.Controls.StackPanel; $sp.Margin='0,0,12,0'; $sp.VerticalAlignment='Center'
    $top=New-Object System.Windows.Controls.TextBlock; $top.FontSize=11.5; $top.Foreground=Get-YumBrush '#F3E8FF'
    $r1=New-Object System.Windows.Documents.Run ($Label+' '); $r1.Foreground=Get-YumBrush '#B8A9C9'
    $r2=New-Object System.Windows.Documents.Run '--'; $r2.FontWeight='SemiBold'
    [void]$top.Inlines.Add($r1); [void]$top.Inlines.Add($r2)
    $bar=New-Object System.Windows.Controls.ProgressBar; $bar.Height=3; $bar.Width=54; $bar.Minimum=0; $bar.Maximum=100; $bar.Margin='0,2,0,0'
    $bar.Foreground=Get-YumBrush $Hex; $bar.Background=Get-YumBrush '#33FFFFFF'; $bar.BorderThickness='0'
    [void]$sp.Children.Add($top); [void]$sp.Children.Add($bar)
    return [pscustomobject]@{Panel=$sp;Value=$r2;Bar=$bar;Hex=$Hex}
}

function Initialize-YumMiniBar {
    if($null -ne $script:Yum['MiniBar']){return $script:Yum['MiniBar']}
    $w=[Windows.Markup.XamlReader]::Parse($script:YumMiniXaml)
    $stats=$w.FindName('Stats')
    $m=@{Window=$w;Ram=(New-YumMiniStat 'RAM' '#CFA8FF');Cpu=(New-YumMiniStat 'CPU' '#FF9ECD');Gpu=(New-YumMiniStat 'GPU' '#B7E3FF');Disk=(New-YumMiniStat 'Disk' '#7DD3FC');Net=(New-YumMiniStat 'Net' '#86EFAC')}
    foreach($k in 'Ram','Cpu','Gpu','Disk','Net'){ [void]$stats.Children.Add($m[$k].Panel) }
    $m.Net.Bar.Visibility='Collapsed'; $m.Net.Panel.ToolTip='Network: download / upload speed right now (all adapters)'   # 5.15.5
    # Position: remembered, else bottom-right above the taskbar. Kept on screen if the display changed.
    $wa=[System.Windows.SystemParameters]::WorkArea
    $left=$null;$top=$null; try{ $left=$script:Yum.Config['MiniBarLeft'];$top=$script:Yum.Config['MiniBarTop'] }catch{}
    $w.WindowStartupLocation='Manual'
    if($null -ne $left -and $null -ne $top -and [double]$left -ge $wa.Left -and [double]$left -lt ($wa.Right-60) -and [double]$top -ge $wa.Top -and [double]$top -lt ($wa.Bottom-30)){ $w.Left=[double]$left; $w.Top=[double]$top }
    else { $w.Left=$wa.Right-560; $w.Top=$wa.Bottom-70 }
    $w.FindName('Shell').Add_MouseLeftButtonDown({ param($s,$e)
        try{ if($e.ClickCount -ge 2){ Show-YumFromMiniBar; return }; $script:Yum['MiniBar'].Window.DragMove()
             Update-YumConfigValue -Name MiniBarLeft -Value ([math]::Round($script:Yum['MiniBar'].Window.Left)); Update-YumConfigValue -Name MiniBarTop -Value ([math]::Round($script:Yum['MiniBar'].Window.Top)) }catch{} })
    $w.FindName('MiniFree').Add_Click({ try{ if(Request-YumMemoryReclaim -Mode Quick){ $script:Yum.TrayReclaimPending=$true; $script:Yum['MiniBar'].Window.FindName('MiniFree').Content='Freeing…' } }catch{ Write-YumLogException -Context 'Mini bar Free RAM failed' -Exception $_.Exception } })
    $w.FindName('MiniOpen').Add_Click({ Show-YumFromMiniBar })
    $hide=$w.FindName('MiniHide')
    $hide.Add_Click({ try{ if($null -ne $script:Yum.TrayIcon){ $script:Yum['MiniBar'].Window.Hide(); Show-YumTrayNotice -Title 'YUMRAM is still running' -Text 'Click the YUMRAM icon near the clock (it may be under the ^ arrow) to bring it back.' } }catch{} })
    $t=New-Object System.Windows.Threading.DispatcherTimer; $t.Interval=[TimeSpan]::FromSeconds(2)
    $t.Add_Tick({ Update-YumMiniBar })
    $m.Timer=$t
    $w.Add_IsVisibleChanged({ try{ $mb=$script:Yum['MiniBar']; if($mb.Window.IsVisible){ Update-YumMiniBar; $mb.Timer.Start() }else{ $mb.Timer.Stop() } }catch{} })
    $script:Yum['MiniBar']=$m
    return $m
}

function Set-YumMiniStat {
    param($Stat,[double]$Percent,[string]$Text,[double]$Warn=70,[double]$Danger=90)
    $Stat.Value.Text=$Text; $Stat.Bar.Value=[math]::Min(100,[math]::Max(0,$Percent))
    $Stat.Bar.Foreground=Get-YumBrush $(if($Percent -ge $Danger){'#F87171'}elseif($Percent -ge $Warn){'#FBBF24'}else{$Stat.Hex})
}

function Update-YumMiniBar {
    $mb=$script:Yum['MiniBar']; if($null -eq $mb -or -not $mb.Window.IsVisible){return}
    try{
        $m=Get-YumMemoryTelemetry
        if($null -ne $m){ Set-YumMiniStat $mb.Ram ([double]$m.UsedPercent) ('{0:N0}%' -f [double]$m.UsedPercent) 70 85; $mb.Ram.Panel.ToolTip=('{0:N1} GB free for programs' -f [double]$m.AvailableGB) }
        $c=Get-YumLiveCpu; if($null -ne $c){ Set-YumMiniStat $mb.Cpu ([double]$c.Percent) ('{0:N0}%' -f [double]$c.Percent) }
        $g=Get-YumLiveGpu; if($null -ne $g){ Set-YumMiniStat $mb.Gpu ([double]$g.Busiest) ('{0:N0}%' -f [double]$g.Busiest) 70 95 }
        $n=Get-YumLiveNetwork; if($null -ne $n){ $mb.Net.Value.Text=('↓{0} ↑{1}' -f (Format-YumNetSpeed $n.Down),(Format-YumNetSpeed $n.Up)) } else { $mb.Net.Value.Text='…' }
        $d=Get-YumLiveDisk; if($null -ne $d -and $null -ne $d.Busiest){ Set-YumMiniStat $mb.Disk ([double]$d.Busiest) ('{0:N0}%' -f [double]$d.Busiest) 60 90 }
        $mb.Window.FindName('MiniHide').IsEnabled=($null -ne $script:Yum.TrayIcon)
        $free=$mb.Window.FindName('MiniFree'); if([string]$free.Content -ne 'Free RAM' -and -not (Test-YumReclaimBusy)){ $free.Content='Free RAM' }
    }catch{}
}

function Show-YumMiniBar {
    # Main window out of the way, mini bar on screen.
    try{
        $mb=Initialize-YumMiniBar
        if($null -ne $script:Yum.Window -and $script:Yum.Window.IsVisible){ $script:Yum.Window.Hide() }
        $mb.Window.Show()
        Write-YumLog 'Mini bar shown.'
    }catch{ Write-YumLogException -Context 'Mini bar failed; using the tray instead' -Exception $_.Exception; try{ Hide-YumToTray }catch{} }
}

function Hide-YumMiniBar { try{ $mb=$script:Yum['MiniBar']; if($null -ne $mb){ $mb.Window.Hide() } }catch{} }

function Show-YumFromMiniBar { Hide-YumMiniBar; Show-YumMainWindow }

function Test-YumMiniBarPreferred { try{ return [bool]$script:Yum.Config['MiniBarOnMinimize'] }catch{ return $false } }

function Close-YumMiniBar {
    try{ $mb=$script:Yum['MiniBar']; if($null -ne $mb){ $mb.Timer.Stop(); $mb.Window.Close(); $script:Yum['MiniBar']=$null } }catch{}
}
