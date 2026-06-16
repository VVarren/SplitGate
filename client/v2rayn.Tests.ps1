$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'v2rayn.ps1')

Describe 'Get-V2raynPath' {
    $tmp = Join-Path $TestDrive 'sample.env'

    It 'extracts the V2RAYN_PATH value' {
        Set-Content $tmp "ALIBABA_REGION=cn-hangzhou`r`nV2RAYN_PATH=C:\apps\v2rayN.exe"
        Get-V2raynPath $tmp | Should Be 'C:\apps\v2rayN.exe'
    }

    It 'ignores surrounding whitespace' {
        Set-Content $tmp 'V2RAYN_PATH =  C:\v\v2rayN.exe '
        Get-V2raynPath $tmp | Should Be 'C:\v\v2rayN.exe'
    }

    It 'throws when the key is missing' {
        Set-Content $tmp 'ALIBABA_REGION=cn-hangzhou'
        { Get-V2raynPath $tmp } | Should Throw
    }
}

Describe 'Start-V2rayn' {
    Context 'when none is running' {
        It 'starts the process' {
            Mock -CommandName Get-Process -MockWith { $null }
            Mock -CommandName Start-Process -MockWith {}
            Start-V2rayn 'C:\apps\v2rayN.exe'
            Assert-MockCalled Start-Process -Exactly 1
        }
    }

    Context 'when already running' {
        It 'does NOT start a second instance' {
            Mock -CommandName Get-Process -MockWith { [pscustomobject]@{ Id = 42 } }
            Mock -CommandName Start-Process -MockWith {}
            Start-V2rayn 'C:\apps\v2rayN.exe'
            Assert-MockCalled Start-Process -Exactly 0
        }
    }
}

Describe 'Stop-V2rayn' {
    Context 'when v2rayN is not running' {
        It 'is a no-op' {
            Mock -CommandName Get-Process -MockWith { $null }
            Mock -CommandName Stop-Process -MockWith {}
            Stop-V2rayn
            Assert-MockCalled Stop-Process -Exactly 0
        }
    }

    Context 'when v2rayN exits gracefully' {
        It 'does not force-kill it' {
            $proc = [pscustomobject]@{ Id = 7; HasExited = $true }
            $proc | Add-Member -MemberType ScriptMethod -Name CloseMainWindow -Value { $true }
            Mock -CommandName Get-Process -MockWith { $proc }
            Mock -CommandName Start-Sleep -MockWith {}
            Mock -CommandName Stop-Process -MockWith {}
            Stop-V2rayn
            Assert-MockCalled Stop-Process -Exactly 0
        }
    }
}

Describe 'Reset-ProxyRegistry' {
    It 'forces ProxyEnable to 0' {
        Mock -CommandName Set-ItemProperty -MockWith {}
        Reset-ProxyRegistry
        Assert-MockCalled Set-ItemProperty -Exactly 1
    }
}
