# v2rayN Orchestration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `proxy on/off/status` control both the Alibaba ECS server and the local v2rayN client with a single command.

**Architecture:** `proxy.py` (pure Alibaba-ECS logic) stays unchanged. A new dot-sourceable PowerShell library `client/v2rayn.ps1` holds all Windows-native logic (launch, graceful shutdown, registry cleanup) as small testable functions. `proxy.ps1` becomes a thin entry point that dot-sources the library and dispatches. Unit tests use Pester 3.4 with mocks; final verification is end-to-end on the real machine.

**Tech Stack:** Windows PowerShell 5.1, Pester 3.4.0, Python (python-dotenv + Alibaba ECS SDK, unchanged), v2rayN v7.

---

## File Structure

- `client/proxy.py` — UNCHANGED. Pure ECS toggle, invoked as a subprocess.
- `client/proxy.ps1` — REWRITTEN. Thin entry: dot-source `v2rayn.ps1`, dispatch `$args[0]`.
- `client/v2rayn.ps1` — NEW. Library of orchestration functions (no top-level execution).
- `client/v2rayn.Tests.ps1` — NEW. Pester 3.4 unit tests for the library.
- `client/.env` — MODIFY. Add `V2RAYN_PATH=...` (gitignored, real value).
- `client/.env.example` — MODIFY. Add `V2RAYN_PATH=...` placeholder.

### Function inventory (defined in `v2rayn.ps1`)

| Function | Signature | Responsibility |
|----------|-----------|----------------|
| `Get-V2raynPath` | `([string]$EnvFile)` → string | Parse `V2RAYN_PATH` value out of a `.env` file; throw if absent |
| `Test-V2raynRunning` | → process or `$null` | Return the running `v2rayN` process object, or `$null` |
| `Start-V2rayn` | `([string]$Path)` | `Start-Process` v2rayN only if not already running |
| `Stop-V2rayn` | → void | Graceful close (`CloseMainWindow` → sleep → force fallback) |
| `Reset-ProxyRegistry` | → void | Force `ProxyEnable=0` in HKCU Internet Settings |
| `Invoke-ProxyPy` | `([string[]]$PyArgs)` | Run `python proxy.py <args>` from the script dir |
| `Invoke-ProxyOn` | → void | Start v2rayN (if down), then `Invoke-ProxyPy on` |
| `Invoke-ProxyOff` | → void | `Stop-V2rayn`, `Reset-ProxyRegistry`, then `Invoke-ProxyPy off` |
| `Invoke-ProxyStatus` | → void | `Invoke-ProxyPy status`, then report v2rayN process state |
| `Invoke-Proxy` | `([string]$Command)` | Validate command and dispatch to the three above |

Script-scoped constants in `v2rayn.ps1`:
```powershell
$script:V2raynProcName = 'v2rayN'   # process name (v2rayN.exe → "v2rayN")
$script:ProxyRegPath   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
```

---

## Task 1: Add V2RAYN_PATH config

**Files:**
- Modify: `client/.env.example`
- Modify: `client/.env`

- [ ] **Step 1: Add placeholder to `.env.example`**

Append this line to `client/.env.example`:
```
V2RAYN_PATH=C:\path\to\v2rayN.exe
```

- [ ] **Step 2: Add the real path to `.env`**

Find the installed v2rayN. Run:
```powershell
Get-ChildItem -Path C:\,$env:USERPROFILE,$env:LOCALAPPDATA -Filter v2rayN.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
```
Append the discovered path to `client/.env`:
```
V2RAYN_PATH=<discovered full path>
```
If not found, ask the user for the path. Do not hardcode it anywhere but `.env`.

- [ ] **Step 3: Commit**

```bash
git add client/.env.example
git commit -m "feat: add V2RAYN_PATH to env example for v2rayN orchestration"
```
(Note: `client/.env` is gitignored — do not commit it.)

---

## Task 2: Create the library skeleton + Get-V2raynPath (TDD)

**Files:**
- Create: `client/v2rayn.ps1`
- Test: `client/v2rayn.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `client/v2rayn.Tests.ps1`:
```powershell
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `powershell -NoProfile -Command "Invoke-Pester -Path client/v2rayn.Tests.ps1"`
Expected: FAIL — `v2rayn.ps1` does not exist / `Get-V2raynPath` not defined.

- [ ] **Step 3: Write minimal implementation**

Create `client/v2rayn.ps1`:
```powershell
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `powershell -NoProfile -Command "Invoke-Pester -Path client/v2rayn.Tests.ps1"`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add client/v2rayn.ps1 client/v2rayn.Tests.ps1
git commit -m "feat: add v2rayn.ps1 library with Get-V2raynPath"
```

---

## Task 3: Process helpers — Test-V2raynRunning & Start-V2rayn (TDD)

**Files:**
- Modify: `client/v2rayn.ps1`
- Modify: `client/v2rayn.Tests.ps1`

- [ ] **Step 1: Write the failing tests**

Append to `client/v2rayn.Tests.ps1`:
```powershell
Describe 'Start-V2rayn' {
    It 'starts the process when none is running' {
        Mock -CommandName Get-Process -MockWith { $null }
        Mock -CommandName Start-Process -MockWith {}
        Start-V2rayn 'C:\apps\v2rayN.exe'
        Assert-MockCalled Start-Process -Exactly 1
    }

    It 'does NOT start a second instance when already running' {
        Mock -CommandName Get-Process -MockWith { [pscustomobject]@{ Id = 42 } }
        Mock -CommandName Start-Process -MockWith {}
        Start-V2rayn 'C:\apps\v2rayN.exe'
        Assert-MockCalled Start-Process -Exactly 0
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `powershell -NoProfile -Command "Invoke-Pester -Path client/v2rayn.Tests.ps1"`
Expected: FAIL — `Start-V2rayn` not defined.

- [ ] **Step 3: Write minimal implementation**

Append to `client/v2rayn.ps1`:
```powershell
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `powershell -NoProfile -Command "Invoke-Pester -Path client/v2rayn.Tests.ps1"`
Expected: PASS (5 tests total).
Note: `Test-V2raynRunning` calls `Get-Process`, which the tests mock — that is why `Start-V2rayn` delegates to it.

- [ ] **Step 5: Commit**

```bash
git add client/v2rayn.ps1 client/v2rayn.Tests.ps1
git commit -m "feat: add Test-V2raynRunning and Start-V2rayn"
```

---

## Task 4: Graceful shutdown — Stop-V2rayn & Reset-ProxyRegistry (TDD)

**Files:**
- Modify: `client/v2rayn.ps1`
- Modify: `client/v2rayn.Tests.ps1`

- [ ] **Step 1: Write the failing tests**

Append to `client/v2rayn.Tests.ps1`:
```powershell
Describe 'Stop-V2rayn' {
    It 'is a no-op when v2rayN is not running' {
        Mock -CommandName Get-Process -MockWith { $null }
        Mock -CommandName Stop-Process -MockWith {}
        Stop-V2rayn
        Assert-MockCalled Stop-Process -Exactly 0
    }

    It 'requests a graceful close when running' {
        $proc = [pscustomobject]@{ HasExited = $true }
        $proc | Add-Member -MemberType ScriptMethod -Name CloseMainWindow -Value { $true }
        Mock -CommandName Get-Process -MockWith { $proc }
        Mock -CommandName Start-Sleep -MockWith {}
        Mock -CommandName Stop-Process -MockWith {}
        Stop-V2rayn
        # HasExited is $true after graceful close, so force-stop must NOT fire
        Assert-MockCalled Stop-Process -Exactly 0
    }
}

Describe 'Reset-ProxyRegistry' {
    It 'forces ProxyEnable to 0' {
        Mock -CommandName Set-ItemProperty -MockWith {}
        Reset-ProxyRegistry
        Assert-MockCalled Set-ItemProperty -Exactly 1
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `powershell -NoProfile -Command "Invoke-Pester -Path client/v2rayn.Tests.ps1"`
Expected: FAIL — `Stop-V2rayn` / `Reset-ProxyRegistry` not defined.

- [ ] **Step 3: Write minimal implementation**

Append to `client/v2rayn.ps1`:
```powershell
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `powershell -NoProfile -Command "Invoke-Pester -Path client/v2rayn.Tests.ps1"`
Expected: PASS (8 tests total).

- [ ] **Step 5: Commit**

```bash
git add client/v2rayn.ps1 client/v2rayn.Tests.ps1
git commit -m "feat: add Stop-V2rayn graceful shutdown and Reset-ProxyRegistry"
```

---

## Task 5: Orchestration & ordering — Invoke-ProxyOn/Off/Status (TDD)

**Files:**
- Modify: `client/v2rayn.ps1`
- Modify: `client/v2rayn.Tests.ps1`

- [ ] **Step 1: Write the failing tests**

Append to `client/v2rayn.Tests.ps1`:
```powershell
Describe 'Invoke-ProxyOn' {
    It 'starts v2rayN then calls python on' {
        $script:order = @()
        Mock -CommandName Get-V2raynPath -MockWith { 'C:\apps\v2rayN.exe' }
        Mock -CommandName Start-V2rayn   -MockWith { $script:order += 'start' }
        Mock -CommandName Invoke-ProxyPy -MockWith { $script:order += "py:$($PyArgs -join ',')" }
        Invoke-ProxyOn
        ($script:order -join '>') | Should Be 'start>py:on'
    }
}

Describe 'Invoke-ProxyOff' {
    It 'closes v2rayN and resets registry BEFORE stopping the instance' {
        $script:order = @()
        Mock -CommandName Stop-V2rayn        -MockWith { $script:order += 'stop' }
        Mock -CommandName Reset-ProxyRegistry -MockWith { $script:order += 'reset' }
        Mock -CommandName Invoke-ProxyPy      -MockWith { $script:order += "py:$($PyArgs -join ',')" }
        Invoke-ProxyOff
        ($script:order -join '>') | Should Be 'stop>reset>py:off'
    }
}

Describe 'Invoke-ProxyStatus' {
    It 'calls python status and reports v2rayN state' {
        Mock -CommandName Invoke-ProxyPy      -MockWith {}
        Mock -CommandName Test-V2raynRunning  -MockWith { [pscustomobject]@{ Id = 1 } }
        Invoke-ProxyStatus
        Assert-MockCalled Invoke-ProxyPy -Exactly 1
    }
}

Describe 'Invoke-Proxy' {
    It 'rejects an unknown command' {
        { Invoke-Proxy 'bogus' } | Should Throw
    }
    It 'dispatches on to Invoke-ProxyOn' {
        Mock -CommandName Invoke-ProxyOn -MockWith {}
        Invoke-Proxy 'on'
        Assert-MockCalled Invoke-ProxyOn -Exactly 1
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `powershell -NoProfile -Command "Invoke-Pester -Path client/v2rayn.Tests.ps1"`
Expected: FAIL — `Invoke-ProxyOn` etc. not defined.

- [ ] **Step 3: Write minimal implementation**

Append to `client/v2rayn.ps1`:
```powershell
function Invoke-ProxyPy {
    param([string[]]$PyArgs)
    $here = $PSScriptRoot
    & python (Join-Path $here 'proxy.py') @PyArgs
}

function Invoke-ProxyOn {
    $envFile = Join-Path $PSScriptRoot '.env'
    Start-V2rayn (Get-V2raynPath $envFile)
    Invoke-ProxyPy 'on'
}

function Invoke-ProxyOff {
    Stop-V2rayn
    Reset-ProxyRegistry
    Invoke-ProxyPy 'off'
}

function Invoke-ProxyStatus {
    Invoke-ProxyPy 'status'
    if (Test-V2raynRunning) {
        Write-Host 'v2rayN: running'
    } else {
        Write-Host 'v2rayN: not running'
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `powershell -NoProfile -Command "Invoke-Pester -Path client/v2rayn.Tests.ps1"`
Expected: PASS (13 tests total).

- [ ] **Step 5: Commit**

```bash
git add client/v2rayn.ps1 client/v2rayn.Tests.ps1
git commit -m "feat: add proxy on/off/status orchestration with ordering guarantees"
```

---

## Task 6: Wire up the entry point

**Files:**
- Modify: `client/proxy.ps1`

- [ ] **Step 1: Replace the passthrough with a dispatcher**

Overwrite `client/proxy.ps1`:
```powershell
. (Join-Path $PSScriptRoot 'v2rayn.ps1')

try {
    Invoke-Proxy -Command $args[0]
    exit 0
} catch {
    Write-Error $_
    exit 1
}
```

- [ ] **Step 2: Confirm Python arg tests still pass**

Run: `cd client && python -m pytest test_proxy_args.py -v`
Expected: PASS (proxy.py is untouched).

- [ ] **Step 3: Confirm bad command is rejected by the entry point**

Run: `powershell -NoProfile -File client/proxy.ps1 bogus; echo "exit=$LASTEXITCODE"`
Expected: prints the Usage error and `exit=1`.

- [ ] **Step 4: Commit**

```bash
git add client/proxy.ps1
git commit -m "feat: make proxy.ps1 orchestrate v2rayN + ECS via v2rayn.ps1"
```

---

## Task 7: End-to-end verification on the real machine

**Files:** none (manual verification)

> This task exercises real ECS billing and the live tunnel. Run deliberately.

- [ ] **Step 1: Status with everything down**

Run: `proxy status`
Expected: prints the ECS instance state (e.g. `Stopped`) AND `v2rayN: not running`.

- [ ] **Step 2: Bring the proxy up**

Run: `proxy on`
Expected: v2rayN window appears; console shows `Starting... Ready. Connect via <EIP>`.
Verify split-tunnel still works (do NOT hammer Bilibili — one call is enough):
```powershell
curl.exe --proxy socks5h://127.0.0.1:10808 https://api.bilibili.com/x/web-interface/zone
```
Expected: country_code 86 (CN exit) for the targeted domain.

- [ ] **Step 2b: Status with everything up**

Run: `proxy status`
Expected: `Running` AND `v2rayN: running`.

- [ ] **Step 3: Bring the proxy down**

Run: `proxy off`
Expected: v2rayN window closes; console shows the registry-reset line and `Stopped. Compute charges paused.`

- [ ] **Step 4: Confirm the registry is clean (the key risk)**

Run:
```powershell
(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings').ProxyEnable
```
Expected: `0`. Confirm normal internet works (open any US site directly).

- [ ] **Step 5: Update README**

Add a short "One-command operation" note to `README.md` documenting that `proxy on/off/status` now manages both ECS and v2rayN, and that `V2RAYN_PATH` must be set in `.env`.

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "docs: document one-command proxy operation"
```

---

## Self-Review Notes

- **Spec coverage:** platform split (Tasks 2-6), V2RAYN_PATH config (Task 1), on/off/status flows + ordering (Task 5), registry-risk mitigation (Tasks 4 & 5, verified Task 7 Step 4), existing Python tests stay green (Task 6 Step 2). All spec sections covered.
- **Type/name consistency:** function names match the inventory table and are used identically across tasks (`Test-V2raynRunning`, `Invoke-ProxyPy`, `$script:ProxyRegPath`, etc.).
- **No placeholders:** every code/test step contains complete content. The only intentional lookup is the real `V2RAYN_PATH` value (Task 1 Step 2), which is machine-specific by design.
