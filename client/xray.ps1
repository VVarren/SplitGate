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
