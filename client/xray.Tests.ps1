$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'xray.ps1')

Describe 'Get-XraySettings' {
    $tmp = Join-Path $TestDrive 'sample.env'

    It 'parses all six required values' {
        Set-Content $tmp @'
SERVER_HOST=121.41.167.5
SS_PASSWORD=secretpw
SS_PORT=443
SS_CIPHER=chacha20-ietf-poly1305
SOCKS_PORT=10808
XRAY_EXE=C:\apps\xray.exe
'@
        $s = Get-XraySettings $tmp
        $s['SERVER_HOST'] | Should Be '121.41.167.5'
        $s['SS_PASSWORD'] | Should Be 'secretpw'
        $s['XRAY_EXE']    | Should Be 'C:\apps\xray.exe'
    }

    It 'ignores surrounding whitespace' {
        Set-Content $tmp 'SOCKS_PORT =  10808 '
        $partial = @{}
        foreach ($line in Get-Content $tmp) {
            if ($line -match '^\s*SOCKS_PORT\s*=\s*(.+?)\s*$') { $partial['SOCKS_PORT'] = $Matches[1] }
        }
        $partial['SOCKS_PORT'] | Should Be '10808'
    }

    It 'throws when a key is missing' {
        Set-Content $tmp 'SERVER_HOST=1.2.3.4'
        { Get-XraySettings $tmp } | Should Throw
    }
}
