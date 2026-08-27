#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Write-Host 'YUMRAM V5.2.74 smoke test'
Write-Host 'Root:' $root
Write-Host 'PowerShell:' $PSVersionTable.PSVersion
foreach($f in @('Config\default-config.json','UI\Xaml\MainWindow.xaml','UI\Xaml\Settings.xaml','UI\Xaml\Intelligence.xaml','Core\Scanner.ps1','Core\Intelligence.ps1','Core\Research.ps1')){if(-not(Test-Path -LiteralPath (Join-Path $root $f))){throw "Missing $f"}}
[xml][IO.File]::ReadAllText((Join-Path $root 'UI\Xaml\MainWindow.xaml'),([System.Text.UTF8Encoding]::new($false,$true)))|Out-Null
[xml][IO.File]::ReadAllText((Join-Path $root 'UI\Xaml\Settings.xaml'),([System.Text.UTF8Encoding]::new($false,$true)))|Out-Null
[xml][IO.File]::ReadAllText((Join-Path $root 'UI\Xaml\Intelligence.xaml'),([System.Text.UTF8Encoding]::new($false,$true)))|Out-Null
[void]([IO.File]::ReadAllText((Join-Path $root 'Config\default-config.json'),([System.Text.UTF8Encoding]::new($false,$true)))|ConvertFrom-Json)
Write-Host 'XAML/JSON syntax: PASS'
Write-Host 'Run StaticTest.ps1 for the full Windows PowerShell 5.1 parser audit.'

