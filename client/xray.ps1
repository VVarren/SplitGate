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
    Set-Content -Path $OutPath -Value $text -Encoding UTF8
    return $OutPath
}
