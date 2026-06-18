. (Join-Path $PSScriptRoot 'xray.ps1')

try {
    Invoke-Proxy -Command $args[0]
    exit 0
} catch {
    Write-Error $_
    exit 1
}
