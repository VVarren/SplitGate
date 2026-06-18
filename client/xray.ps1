$script:XrayProcName = 'xray'
$script:ProxyRegPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$script:RuntimeDir   = Join-Path $PSScriptRoot '.xray'

function Get-XraySettings {
    param([string]$EnvFile)
    $keys = 'SERVER_HOST','SS_PASSWORD','SS_PORT','SS_CIPHER','SOCKS_PORT','XRAY_EXE'
    $values = @{}
    foreach ($line in Get-Content $EnvFile) {
        foreach ($key in $keys) {
            if ($line -match "^\s*$key\s*=\s*(.+?)\s*$") { $values[$key] = $Matches[1] }
        }
    }
    $missing = $keys | Where-Object { -not $values.ContainsKey($_) }
    if ($missing) { throw "Missing env vars: $($missing -join ', ')" }
    return $values
}

function New-XrayConfig {
    param([string]$TemplatePath, [hashtable]$Values, [string]$OutPath)
    $text = Get-Content $TemplatePath -Raw
    $map = @{
        '__SERVER_HOST__' = $Values['SERVER_HOST']
        '__SS_PASSWORD__' = $Values['SS_PASSWORD']
        '__SS_PORT__'     = $Values['SS_PORT']
        '__SS_CIPHER__'   = $Values['SS_CIPHER']
        '__SOCKS_PORT__'  = $Values['SOCKS_PORT']
    }
    foreach ($token in $map.Keys) { $text = $text.Replace($token, $map[$token]) }
    if ($text -match '__[A-Z_]+__') { throw "Unsubstituted token in rendered config: $($Matches[0])" }
    $dir = Split-Path -Parent $OutPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    # xray's JSON parser rejects a UTF-8 BOM. PS 5.1 'Set-Content -Encoding UTF8' writes one,
    # so write the bytes ourselves with a BOM-less UTF-8 encoder.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($OutPath, $text, $utf8NoBom)
    return $OutPath
}

function Get-XrayPidFile { param([string]$RuntimeDir) Join-Path $RuntimeDir 'xray.pid' }

function Test-XrayRunning {
    param([string]$RuntimeDir)
    $pidFile = Get-XrayPidFile $RuntimeDir
    if (-not (Test-Path $pidFile)) { return $null }
    $procId = (Get-Content $pidFile | Select-Object -First 1)
    $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
    if ($proc -and $proc.Name -eq $script:XrayProcName) { return $proc }
    return $null
}

function Start-Xray {
    param([string]$XrayExe, [string]$ConfigPath, [string]$RuntimeDir)
    if (Test-XrayRunning $RuntimeDir) { Write-Host 'xray already running.'; return }
    if (-not (Test-Path $RuntimeDir)) { New-Item -ItemType Directory -Path $RuntimeDir -Force | Out-Null }
    $log    = Join-Path $RuntimeDir 'xray.log'
    $errLog = Join-Path $RuntimeDir 'xray.err.log'
    $proc = Start-Process -FilePath $XrayExe `
        -ArgumentList @('-c', $ConfigPath) `
        -WorkingDirectory (Split-Path -Parent $XrayExe) `
        -WindowStyle Hidden `
        -RedirectStandardOutput $log `
        -RedirectStandardError $errLog `
        -PassThru
    Set-Content -Path (Get-XrayPidFile $RuntimeDir) -Value $proc.Id
    Start-Sleep -Seconds 1
    if ($proc.HasExited) {
        $tail = Get-Content $log -Tail 20 -ErrorAction SilentlyContinue
        throw "xray exited immediately. Log tail:`n$($tail -join "`n")"
    }
    Write-Host "Launched xray (PID $($proc.Id))."
}

function Stop-Xray {
    param([string]$RuntimeDir)
    $proc = Test-XrayRunning $RuntimeDir
    if (-not $proc) { Write-Host 'xray not running.'; return }
    Stop-Process -Id $proc.Id -Force
    Remove-Item (Get-XrayPidFile $RuntimeDir) -ErrorAction SilentlyContinue
    Write-Host 'Stopped xray.'
}

function Set-SystemProxy {
    param([string]$SocksPort)
    Set-ItemProperty -Path $script:ProxyRegPath -Name ProxyServer -Value "127.0.0.1:$SocksPort"
    Set-ItemProperty -Path $script:ProxyRegPath -Name ProxyEnable -Value 1
    Write-Host "System proxy set to 127.0.0.1:$SocksPort."
}

function Reset-ProxyRegistry {
    Set-ItemProperty -Path $script:ProxyRegPath -Name ProxyEnable -Value 0 -ErrorAction SilentlyContinue
    Write-Host 'System proxy registry reset (ProxyEnable=0).'
}

function Invoke-ProxyPy {
    param([string[]]$PyArgs)
    & python (Join-Path $PSScriptRoot 'proxy.py') @PyArgs
}

function Invoke-ProxyOn {
    $envFile  = Join-Path $PSScriptRoot '.env'
    $template = Join-Path $PSScriptRoot 'xray-config.template.json'
    $settings = Get-XraySettings $envFile
    $config   = New-XrayConfig $template $settings (Join-Path $script:RuntimeDir 'config.json')
    Invoke-ProxyPy 'on'
    Start-Xray $settings['XRAY_EXE'] $config $script:RuntimeDir
    Set-SystemProxy $settings['SOCKS_PORT']
}

function Invoke-ProxyOff {
    Reset-ProxyRegistry
    Stop-Xray $script:RuntimeDir
    Invoke-ProxyPy 'off'
}

function Invoke-ProxyStatus {
    Invoke-ProxyPy 'status'
    if (Test-XrayRunning $script:RuntimeDir) { Write-Host 'xray: running' } else { Write-Host 'xray: not running' }
    if (Get-Process -Name 'v2rayN' -ErrorAction SilentlyContinue) {
        Write-Host 'WARNING: v2rayN is running and may contend for the SOCKS port.'
    }
}

function Invoke-Proxy {
    param([string]$Command)
    switch ($Command) {
        'on'     { Invoke-ProxyOn }
        'off'    { Invoke-ProxyOff }
        'status' { Invoke-ProxyStatus }
        default  { throw "Usage: proxy <on | off | status>" }
    }
}
