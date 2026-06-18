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

Describe 'New-XrayConfig' {
    $template = Join-Path $TestDrive 'tmpl.json'
    $out      = Join-Path $TestDrive 'out\config.json'
    Set-Content $template '{ "address": "__SERVER_HOST__", "port": __SS_PORT__, "pw": "__SS_PASSWORD__", "m": "__SS_CIPHER__", "in": __SOCKS_PORT__ }'

    $values = @{
        SERVER_HOST = '121.41.167.5'; SS_PASSWORD = 'pw1'; SS_PORT = '443'
        SS_CIPHER = 'chacha20-ietf-poly1305'; SOCKS_PORT = '10808'
    }

    It 'substitutes all tokens and writes valid JSON' {
        New-XrayConfig $template $values $out | Should Be $out
        $json = Get-Content $out -Raw | ConvertFrom-Json
        $json.address | Should Be '121.41.167.5'
        $json.port    | Should Be 443
        $json.in      | Should Be 10808
        $json.pw      | Should Be 'pw1'
    }

    It 'writes the file without a UTF-8 BOM (xray rejects a BOM)' {
        New-XrayConfig $template $values $out | Out-Null
        $bytes = [System.IO.File]::ReadAllBytes($out)
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should Be $false
    }

    It 'throws when a token is left unsubstituted' {
        Set-Content $template '{ "x": "__SERVER_HOST__", "y": "__UNKNOWN__" }'
        { New-XrayConfig $template $values $out } | Should Throw
    }
}

Describe 'Test-XrayRunning' {
    Context 'when pidfile points at a live xray process' {
        It 'returns the process' {
            $rt = Join-Path $TestDrive 'rt1'; New-Item -ItemType Directory $rt -Force | Out-Null
            Set-Content (Join-Path $rt 'xray.pid') '123'
            Mock -CommandName Get-Process -MockWith { [pscustomobject]@{ Id = 123; Name = 'xray' } }
            (Test-XrayRunning $rt).Id | Should Be 123
        }
    }
    Context 'when no pidfile exists' {
        It 'returns null' {
            $rt = Join-Path $TestDrive 'rt2'; New-Item -ItemType Directory $rt -Force | Out-Null
            Test-XrayRunning $rt | Should Be $null
        }
    }
    Context 'when pid was reused by a non-xray process' {
        It 'returns null' {
            $rt = Join-Path $TestDrive 'rt3'; New-Item -ItemType Directory $rt -Force | Out-Null
            Set-Content (Join-Path $rt 'xray.pid') '123'
            Mock -CommandName Get-Process -MockWith { [pscustomobject]@{ Id = 123; Name = 'notepad' } }
            Test-XrayRunning $rt | Should Be $null
        }
    }
}

Describe 'Start-Xray' {
    Context 'when not already running' {
        It 'launches xray and writes the pidfile' {
            $rt = Join-Path $TestDrive 'srt1'; New-Item -ItemType Directory $rt -Force | Out-Null
            Mock -CommandName Test-XrayRunning -MockWith { $null }
            Mock -CommandName Start-Process -MockWith { [pscustomobject]@{ Id = 555; HasExited = $false } }
            Mock -CommandName Start-Sleep -MockWith {}
            Start-Xray 'C:\apps\xray.exe' 'C:\cfg.json' $rt
            Get-Content (Join-Path $rt 'xray.pid') | Should Be '555'
        }
    }
    Context 'when xray exits immediately' {
        It 'throws' {
            $rt = Join-Path $TestDrive 'srt2'; New-Item -ItemType Directory $rt -Force | Out-Null
            Mock -CommandName Test-XrayRunning -MockWith { $null }
            Mock -CommandName Start-Process -MockWith { [pscustomobject]@{ Id = 556; HasExited = $true } }
            Mock -CommandName Start-Sleep -MockWith {}
            { Start-Xray 'C:\apps\xray.exe' 'C:\cfg.json' $rt } | Should Throw
        }
    }
    Context 'when already running' {
        It 'does not launch a second instance' {
            $rt = Join-Path $TestDrive 'srt3'; New-Item -ItemType Directory $rt -Force | Out-Null
            Mock -CommandName Test-XrayRunning -MockWith { [pscustomobject]@{ Id = 1 } }
            Mock -CommandName Start-Process -MockWith {}
            Start-Xray 'C:\apps\xray.exe' 'C:\cfg.json' $rt
            Assert-MockCalled Start-Process -Exactly 0
        }
    }
}

Describe 'Stop-Xray' {
    Context 'when not running' {
        It 'is a no-op' {
            Mock -CommandName Test-XrayRunning -MockWith { $null }
            Mock -CommandName Stop-Process -MockWith {}
            Stop-Xray (Join-Path $TestDrive 'xrt1')
            Assert-MockCalled Stop-Process -Exactly 0
        }
    }
    Context 'when running' {
        It 'stops the process' {
            $rt = Join-Path $TestDrive 'xrt2'; New-Item -ItemType Directory $rt -Force | Out-Null
            Set-Content (Join-Path $rt 'xray.pid') '777'
            Mock -CommandName Test-XrayRunning -MockWith { [pscustomobject]@{ Id = 777; Name = 'xray' } }
            Mock -CommandName Stop-Process -MockWith {}
            Stop-Xray $rt
            Assert-MockCalled Stop-Process -Exactly 1
        }
    }
}

Describe 'Set-SystemProxy' {
    It 'writes ProxyServer and ProxyEnable' {
        Mock -CommandName Set-ItemProperty -MockWith {}
        Set-SystemProxy '10808'
        Assert-MockCalled Set-ItemProperty -Exactly 2
    }
}

Describe 'Reset-ProxyRegistry' {
    It 'forces ProxyEnable to 0' {
        Mock -CommandName Set-ItemProperty -MockWith {}
        Reset-ProxyRegistry
        Assert-MockCalled Set-ItemProperty -Exactly 1
    }
}

Describe 'Invoke-ProxyOn' {
    It 'renders config, starts server, starts xray, sets proxy IN ORDER' {
        $script:order = @()
        Mock -CommandName Get-XraySettings -MockWith { @{ XRAY_EXE='x'; SOCKS_PORT='10808' } }
        Mock -CommandName New-XrayConfig   -MockWith { $script:order += 'render'; 'cfg.json' }
        Mock -CommandName Invoke-ProxyPy   -MockWith { $script:order += "py:$($PyArgs -join ',')" }
        Mock -CommandName Start-Xray       -MockWith { $script:order += 'start' }
        Mock -CommandName Set-SystemProxy  -MockWith { $script:order += 'set' }
        Invoke-ProxyOn
        ($script:order -join '>') | Should Be 'render>py:on>start>set'
    }
}

Describe 'Invoke-ProxyOff' {
    It 'resets registry, stops xray, then stops the instance IN ORDER' {
        $script:order = @()
        Mock -CommandName Reset-ProxyRegistry -MockWith { $script:order += 'reset' }
        Mock -CommandName Stop-Xray           -MockWith { $script:order += 'stop' }
        Mock -CommandName Invoke-ProxyPy      -MockWith { $script:order += "py:$($PyArgs -join ',')" }
        Invoke-ProxyOff
        ($script:order -join '>') | Should Be 'reset>stop>py:off'
    }
}

Describe 'Invoke-ProxyStatus' {
    It 'calls python status' {
        Mock -CommandName Invoke-ProxyPy    -MockWith {}
        Mock -CommandName Test-XrayRunning   -MockWith { $null }
        Mock -CommandName Get-Process        -MockWith { $null }
        Invoke-ProxyStatus
        Assert-MockCalled Invoke-ProxyPy -Exactly 1
    }
}

Describe 'Invoke-Proxy' {
    Context 'with an unknown command' {
        It 'throws' { { Invoke-Proxy 'bogus' } | Should Throw }
    }
    Context 'with on' {
        It 'dispatches to Invoke-ProxyOn' {
            Mock -CommandName Invoke-ProxyOn -MockWith {}
            Invoke-Proxy 'on'
            Assert-MockCalled Invoke-ProxyOn -Exactly 1
        }
    }
}
