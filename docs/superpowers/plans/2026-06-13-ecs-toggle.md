# ECS Toggle CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `proxy on/off/status` CLI commands that start/stop the Alibaba Cloud ECS instance on demand to avoid compute charges when not in use.

**Architecture:** A Python script (`proxy.py`) validates the command before loading credentials, then uses the Alibaba Cloud ECS SDK to start/stop the instance and polls until the target state is reached. A PowerShell wrapper (`proxy.ps1`) on the Windows PATH delegates to it, enabling `proxy on/off/status` from any terminal. Credentials are loaded from a gitignored `.env` file in `client/`.

**Tech Stack:** Python 3, alibabacloud-ecs20140526, alibabacloud-tea-openapi, python-dotenv, PowerShell

---

### Task 1: Dependencies and .env setup

**Files:**
- Create: `client/requirements.txt`
- Create: `client/.env.example`
- Modify: `.gitignore`

- [ ] **Step 1: Create `client/requirements.txt`**

```
alibabacloud-ecs20140526>=3.0.0
alibabacloud-tea-openapi>=0.3.7
python-dotenv>=1.0.0
pytest>=7.0.0
```

- [ ] **Step 2: Create `client/.env.example`**

```env
ALIBABA_ACCESS_KEY_ID=your_access_key_id
ALIBABA_ACCESS_KEY_SECRET=your_access_key_secret
ALIBABA_INSTANCE_ID=your_instance_id
ALIBABA_REGION=cn-hangzhou
PROXY_EIP=your.eip.address
```

- [ ] **Step 3: Add `client/.env` to `.gitignore`**

Add this line to `.gitignore` at the repo root:

```
client/.env
```

- [ ] **Step 4: Install dependencies**

```bash
pip install -r client/requirements.txt
```

Expected: all packages install without errors.

- [ ] **Step 5: Copy `.env.example` to `client/.env` and fill in your values**

```env
ALIBABA_ACCESS_KEY_ID=<from Alibaba Cloud console → RAM → Access Keys>
ALIBABA_ACCESS_KEY_SECRET=<from Alibaba Cloud console → RAM → Access Keys>
ALIBABA_INSTANCE_ID=i-bp11sm8itoivpwo36hv1
ALIBABA_REGION=cn-hangzhou
PROXY_EIP=121.41.167.5
```

- [ ] **Step 6: Commit**

```bash
git add client/requirements.txt client/.env.example .gitignore
git commit -m "feat: add ECS toggle CLI dependencies and env template"
```

---

### Task 2: proxy.py — main CLI script

**Files:**
- Create: `client/proxy.py`
- Create: `client/test_proxy_args.py`

- [ ] **Step 1: Write the failing test for argument validation**

Create `client/test_proxy_args.py`:

```python
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).parent

def _run(args):
    return subprocess.run(
        [sys.executable, 'proxy.py'] + args,
        capture_output=True, text=True,
        cwd=HERE
    )

def test_no_args_prints_usage_and_exits_1():
    r = _run([])
    assert r.returncode == 1
    assert 'Usage' in r.stderr

def test_unknown_command_prints_usage_and_exits_1():
    r = _run(['foo'])
    assert r.returncode == 1
    assert 'Usage' in r.stderr
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd client && python -m pytest test_proxy_args.py -v
```

Expected: `FileNotFoundError` or `ModuleNotFoundError` — `proxy.py` doesn't exist yet.

- [ ] **Step 3: Create `client/proxy.py`**

```python
import os
import sys
import time
from pathlib import Path

from alibabacloud_ecs20140526 import models as ecs_models
from alibabacloud_ecs20140526.client import Client
from alibabacloud_tea_openapi import models as open_api_models
from dotenv import load_dotenv

COMMANDS = {'on', 'off', 'status'}


def _make_client(access_key_id, access_key_secret, region):
    config = open_api_models.Config(
        access_key_id=access_key_id,
        access_key_secret=access_key_secret,
        region_id=region,
    )
    return Client(config)


def _get_status(client, region, instance_id):
    req = ecs_models.DescribeInstanceStatusRequest(
        region_id=region,
        instance_id=[instance_id],
    )
    resp = client.describe_instance_status(req)
    return resp.body.instance_statuses.instance_status[0].status


def _wait_for(client, region, instance_id, target):
    while True:
        if _get_status(client, region, instance_id) == target:
            return
        time.sleep(5)


def _on(client, region, instance_id, eip):
    if _get_status(client, region, instance_id) == 'Running':
        print('Already running.')
        return
    client.start_instance(ecs_models.StartInstanceRequest(instance_id=instance_id))
    print('Starting...', end='', flush=True)
    _wait_for(client, region, instance_id, 'Running')
    print(f' Ready. Connect via {eip}')


def _off(client, region, instance_id):
    if _get_status(client, region, instance_id) == 'Stopped':
        print('Already stopped.')
        return
    client.stop_instance(ecs_models.StopInstanceRequest(
        instance_id=instance_id,
        stopped_mode='StopCharging',
        force_stop=False,
    ))
    print('Stopping...', end='', flush=True)
    _wait_for(client, region, instance_id, 'Stopped')
    print(' Stopped. Compute charges paused.')


def _status(client, region, instance_id):
    print(_get_status(client, region, instance_id))


def main(argv=None):
    if argv is None:
        argv = sys.argv[1:]

    if len(argv) != 1 or argv[0] not in COMMANDS:
        print(f'Usage: proxy <{" | ".join(sorted(COMMANDS))}>', file=sys.stderr)
        return 1

    load_dotenv(Path(__file__).parent / '.env')
    access_key_id = os.environ['ALIBABA_ACCESS_KEY_ID']
    access_key_secret = os.environ['ALIBABA_ACCESS_KEY_SECRET']
    instance_id = os.environ['ALIBABA_INSTANCE_ID']
    region = os.environ['ALIBABA_REGION']
    eip = os.environ['PROXY_EIP']

    client = _make_client(access_key_id, access_key_secret, region)

    if argv[0] == 'on':
        _on(client, region, instance_id, eip)
    elif argv[0] == 'off':
        _off(client, region, instance_id)
    elif argv[0] == 'status':
        _status(client, region, instance_id)

    return 0


if __name__ == '__main__':
    sys.exit(main())
```

- [ ] **Step 4: Run the argument tests**

```bash
cd client && python -m pytest test_proxy_args.py -v
```

Expected:
```
PASSED test_proxy_args.py::test_no_args_prints_usage_and_exits_1
PASSED test_proxy_args.py::test_unknown_command_prints_usage_and_exits_1
```

- [ ] **Step 5: Manually verify `proxy status` connects to the API**

```bash
cd client && python proxy.py status
```

Expected: one of `Running`, `Stopped`, `Starting`, `Stopping` — whatever the instance is currently in. If you see an auth error, double-check your `.env` values.

- [ ] **Step 6: Commit**

```bash
git add client/proxy.py client/test_proxy_args.py
git commit -m "feat: add proxy.py ECS toggle CLI"
```

---

### Task 3: proxy.ps1 — PowerShell wrapper

**Files:**
- Create: `client/proxy.ps1`

- [ ] **Step 1: Create `client/proxy.ps1`**

```powershell
python "$PSScriptRoot\proxy.py" $args
```

- [ ] **Step 2: Add `client/` to Windows PATH permanently (one-time setup)**

Open PowerShell **as Administrator** and run:

```powershell
[Environment]::SetEnvironmentVariable(
    'PATH',
    [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';C:\dev\Personal\proxy\client',
    [EnvironmentVariableTarget]::Machine
)
```

Then **open a new terminal** for the PATH change to take effect.

- [ ] **Step 3: Verify `proxy` works from any directory**

Open a new terminal (not in the proxy repo) and run:

```powershell
proxy status
```

Expected: `Running` or `Stopped` — same output as `python proxy.py status` from within `client/`.

- [ ] **Step 4: Commit**

```bash
git add client/proxy.ps1
git commit -m "feat: add proxy.ps1 PowerShell wrapper"
```

---

### Task 4: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add CLI toggle section to README**

Add the following new section after the existing `## 4. Verify` section in `README.md`:

```markdown
---

## 5. CLI Toggle (Start / Stop the VPS)

Install dependencies once:

```bash
pip install -r client/requirements.txt
```

Copy the credential template and fill in your values:

```bash
cp client/.env.example client/.env
# Edit client/.env — Access Key from Alibaba Cloud console → RAM → Access Keys
```

Add `client/` to your Windows PATH permanently (PowerShell as Administrator, once):

```powershell
[Environment]::SetEnvironmentVariable(
    'PATH',
    [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';C:\dev\Personal\proxy\client',
    [EnvironmentVariableTarget]::Machine
)
```

Restart your terminal, then:

```
proxy on       # Start the VPS — prints the EIP when ready
proxy off      # Stop the VPS in economical mode (no compute charges)
proxy status   # Show current instance state
```

> After `proxy off`, disable the system proxy in v2rayN: tray icon → System proxy → Clear system proxy.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add CLI toggle setup and usage to README"
```

---

## Final Verification

- [ ] Run `proxy on` — output ends with `Ready. Connect via 121.41.167.5`
- [ ] Open Alibaba Cloud ECS console — instance shows `Running`
- [ ] Run `proxy status` — prints `Running`
- [ ] Run `proxy off` — output ends with `Stopped. Compute charges paused.`
- [ ] Open Alibaba Cloud ECS console — instance shows `Stopped`
- [ ] Run `proxy on` when already running — prints `Already running.`
- [ ] Run `proxy off` when already stopped — prints `Already stopped.`
