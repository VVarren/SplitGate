# ECS Toggle CLI — Design Spec

**Date:** 2026-06-13  
**Goal:** Add an on/off CLI command to start/stop the Alibaba Cloud ECS instance on demand, avoiding compute charges when the proxy is not in use.

---

## Architecture

Three new files added under `client/`:

```
proxy/
  client/
    proxy.py        # Python script — Alibaba SDK logic
    proxy.ps1       # PowerShell wrapper — delegates to proxy.py
    .env            # Credentials (gitignored)
    .env.example    # Template committed to repo
    routing.json    # (existing)
```

`proxy.ps1` is added to the Windows PATH once. After that, `proxy on/off/status` works from any terminal. `proxy.py` reads `.env`, calls the Alibaba Cloud ECS Python SDK, and polls until the instance reaches the target state before exiting.

---

## Commands & Behavior

```
proxy on      # Start ECS instance, wait until Running, print EIP address
proxy off     # Stop ECS instance (StopCharging mode), wait until Stopped, confirm
proxy status  # Print current instance state (Running/Stopped/Starting/Stopping/etc.)
```

**Details:**
- `proxy on` polls every 5 seconds until state is `Running`, then prints the EIP so the user knows it's ready
- `proxy off` uses `StoppedMode='StopCharging'` (Alibaba's economical/no-charges-after-stop mode) — releases vCPU/memory billing while stopped
- `proxy off` polls every 5 seconds until state is `Stopped`, then confirms
- If already in the target state, prints a message and exits cleanly (idempotent)
- All output is a single clear line — no noise

**v2rayN:** Not automated. The EIP is static so the v2rayN server config never needs updating. User manually toggles the system proxy in the v2rayN tray icon when needed.

---

## Credentials & `.env`

`.env` file location: `client/.env` (gitignored)

```env
ALIBABA_ACCESS_KEY_ID=your_key_here
ALIBABA_ACCESS_KEY_SECRET=your_secret_here
ALIBABA_INSTANCE_ID=i-bp11sm8itoivpwo36hv1
ALIBABA_REGION=cn-hangzhou
```

- Obtain Access Key from Alibaba Cloud console → RAM → Access Keys
- `.env.example` with placeholder values is committed to the repo
- `proxy.py` loads credentials via `python-dotenv`

---

## PowerShell Wrapper

`client/proxy.ps1` — one line:
```powershell
python "$PSScriptRoot\proxy.py" $args
```

**PATH setup (one-time):** Add `C:\dev\Personal\proxy\client` to the Windows system PATH via System Environment Variables. README documents this step so it survives reboots.

---

## Dependencies

- `alibabacloud-ecs20140526` — Alibaba Cloud ECS SDK
- `alibabacloud-tea-openapi` — SDK authentication
- `python-dotenv` — `.env` loading

All listed in `client/requirements.txt`.

---

## EIP Note

The ECS instance has a static EIP bound to it. The EIP remains associated even when the instance is stopped, so the IP never changes and the v2rayN config remains valid indefinitely. Check the Alibaba Cloud billing console for EIP idle fees — these vary by EIP billing type and may apply while the instance is stopped.
