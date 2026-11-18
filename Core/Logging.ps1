function Get-YumLogPath {
    try {
        if ($null -eq $script:Yum) { return $null }
        $fileName = [string]$script:Yum.Config.LogFileName
        if ([string]::IsNullOrWhiteSpace($fileName)) { $fileName = 'YUMRAM.log' }
        if ([IO.Path]::IsPathRooted($fileName)) { return $fileName }
        return (Join-Path $script:Yum.ConfigDirectory $fileName)
    } catch { return $null }
}

function Write-YumLog {
    param([Parameter(Mandatory)][string]$Message)
    try {
        if ($null -eq $script:Yum -or $null -eq $script:Yum.Config) { return }
        if (-not [bool]$script:Yum.Config.Logging) { return }
        $path = Get-YumLogPath
        if ([string]::IsNullOrWhiteSpace($path)) { return }
        $folder = Split-Path -Parent $path
        if ($folder -and -not (Test-Path -LiteralPath $folder)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
        }
        $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message
        [System.Threading.Monitor]::Enter($script:Yum.LogLock)
        try { Add-Content -LiteralPath $path -Value $line -Encoding UTF8 } finally { [System.Threading.Monitor]::Exit($script:Yum.LogLock) }
    } catch { }
}

function Write-YumLogException {
    param([string]$Context,[System.Exception]$Exception)
    $message = if ($Exception) { $Exception.Message } else { 'Unknown error' }
    Write-YumLog ("{0}: {1}" -f $Context,$message)
}
