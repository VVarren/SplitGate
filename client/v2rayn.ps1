$script:V2raynProcName = 'v2rayN'
$script:ProxyRegPath   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'

function Get-V2raynPath {
    param([string]$EnvFile)
    foreach ($line in Get-Content $EnvFile) {
        if ($line -match '^\s*V2RAYN_PATH\s*=\s*(.+?)\s*$') {
            return $Matches[1]
        }
    }
    throw "V2RAYN_PATH not found in $EnvFile"
}

function Test-V2raynRunning {
    Get-Process -Name $script:V2raynProcName -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Start-V2rayn {
    param([string]$Path)
    if (Test-V2raynRunning) {
        Write-Host 'v2rayN already running.'
        return
    }
    Start-Process -FilePath $Path
    Write-Host 'Launched v2rayN.'
}

function Stop-V2rayn {
    $proc = Test-V2raynRunning
    if (-not $proc) {
        Write-Host 'v2rayN not running.'
        return
    }
    Write-Host 'Closing v2rayN...'
    [void]$proc.CloseMainWindow()
    Start-Sleep -Seconds 2
    if (-not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
}

function Reset-ProxyRegistry {
    Set-ItemProperty -Path $script:ProxyRegPath -Name ProxyEnable -Value 0 -ErrorAction SilentlyContinue
    Write-Host 'System proxy registry reset (ProxyEnable=0).'
}
