#requires -Version 5.1
# 5.15: "Help everyone" - shows exactly what would be shared from "Measure games" and lets the user decide.

function Show-YumCommunityShareDialog {
    # Returns $true when the user shared. -Reason explains why it is shown (after a benchmark / from Settings).
    param([string]$Reason='')
    try{
        $kn=Get-YumCpuKnowledge
        $payload=New-YumCommunityPayload -Knowledge $kn
        if($null -eq $payload){ Show-YumMessage -Message 'There are no game benchmark results on this PC yet. Run Settings › CPU › "Measure games on this PC" first.' -Title 'YUMRAM - Share results' -Buttons 'OK' -Icon 'Information'; return $false }
        $text=ConvertTo-YumCommunityText -Payload $payload
        $cfg=Get-YumCommunityConfig
        $how=if($cfg.Endpoint -match '^https://'){'It is sent to the YUMRAM results server over HTTPS.'}else{'Your browser opens a pre-filled GitHub issue; press Create there to share (a GitHub account is needed).'}
        $xaml=@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="YUMRAM - Help everyone" Width="640" Height="600" WindowStartupLocation="CenterOwner" ResizeMode="CanResize"
        Background="{StaticResource Bg}" Foreground="{StaticResource Text}" FontFamily="{StaticResource UiFont}" FontSize="14">
  <Grid Margin="20,16,20,14">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel>
      <TextBlock Text="Share your game results to help everyone?" FontSize="19" FontWeight="SemiBold" Foreground="{StaticResource Brand}" TextWrapping="Wrap"/>
      <TextBlock x:Name="Intro" Style="{StaticResource Caption}" TextWrapping="Wrap" Margin="0,6,0,10"/>
      <TextBlock Text="EXACTLY WHAT WOULD BE SHARED" Style="{StaticResource StatLabel}" Margin="0,0,0,4"/>
    </StackPanel>
    <TextBox x:Name="Data" Grid.Row="1" IsReadOnly="True" FontFamily="Consolas" FontSize="12" TextWrapping="NoWrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" Background="{StaticResource Surface2}" Foreground="{StaticResource Text}" BorderThickness="0" Padding="8"/>
    <CheckBox x:Name="Always" Grid.Row="2" Content="Always share my results after a game benchmark (you can turn this off in Settings › Privacy)" Margin="0,10,0,0" Foreground="{StaticResource Text}"/>
    <DockPanel Grid.Row="3" Margin="0,12,0,0">
      <Button x:Name="Share" DockPanel.Dock="Right" Content="Share" Style="{StaticResource PrimaryButton}" MinWidth="100" Margin="8,0,0,0"/>
      <Button x:Name="NotNow" DockPanel.Dock="Right" Content="Not now" MinWidth="100"/>
      <TextBlock x:Name="How" Style="{StaticResource Caption}" TextWrapping="Wrap" VerticalAlignment="Center"/>
    </DockPanel>
  </Grid>
</Window>
"@
        $w=[Windows.Markup.XamlReader]::Parse($xaml)
        $w.FindName('Intro').Text=(('{0}Other people with a CPU like yours get good game settings from these numbers before they run any benchmark. Only what is shown below is shared: your CPU model and layout, laptop or desktop, Windows build, YUMRAM version and the frame rates YUMRAM''s own test game reached. No program names, files, user or PC names, and no ID that identifies you.' -f $(if($Reason){$Reason+' '}else{''})))
        $w.FindName('Data').Text=$text
        $w.FindName('How').Text=$how
        $w.FindName('Always').IsChecked=[bool]$cfg.Share
        $state=@{Shared=$false;Window=$w;Payload=$payload}
        foreach($n in 'Share','NotNow'){ $w.FindName($n).Tag=$state }
        $w.FindName('NotNow').Add_Click({param($s,$e) $s.Tag.Window.Close()})
        $w.FindName('Share').Add_Click({param($s,$e)
            $st=$s.Tag
            $r=Send-YumCommunityResults -Payload $st.Payload
            $st.Shared=[bool]$r.Success
            try{ Show-YumToast -Kind $(if($r.Success){'Ok'}else{'Warn'}) -Text ([string]$r.Reason) }catch{}
            $st.Window.Close()
        })
        try{ $w.Owner=$script:Yum.Window }catch{}
        [void]$w.ShowDialog()
        Update-YumConfigValue -Name CommunityAsked -Value $true
        Update-YumConfigValue -Name CommunityShareEnabled -Value ([bool]$w.FindName('Always').IsChecked)
        return [bool]$state.Shared
    }catch{
        Write-YumLogException -Context 'Community share dialog failed' -Exception $_.Exception
        return $false
    }
}

function Invoke-YumCommunityAfterBenchmark {
    # Called on the UI thread once a benchmark has finished: share automatically if the user opted in,
    # ask once if they never decided, otherwise stay quiet.
    try{
        $cfg=Get-YumCommunityConfig
        $payload=New-YumCommunityPayload -Knowledge (Get-YumCpuKnowledge)
        if($null -eq $payload){return}
        if($cfg.Share){
            $r=Send-YumCommunityResults -Payload $payload
            try{ Show-YumToast -Kind $(if($r.Success){'Ok'}else{'Warn'}) -Text ([string]$r.Reason) }catch{}
            return
        }
        $asked=$false;try{$asked=[bool]$script:Yum.Config['CommunityAsked']}catch{}
        if(-not $asked){ [void](Show-YumCommunityShareDialog -Reason 'Game measurement finished.') }
    }catch{ try{Write-YumLogException -Context 'Community after-benchmark step failed' -Exception $_.Exception}catch{} }
}
