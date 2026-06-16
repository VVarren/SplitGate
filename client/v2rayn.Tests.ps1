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
