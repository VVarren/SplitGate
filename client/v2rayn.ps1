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
