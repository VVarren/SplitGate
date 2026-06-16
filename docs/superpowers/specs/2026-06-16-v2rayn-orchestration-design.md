# Design: one-command proxy (server + v2rayN orchestration)

**Date:** 2026-06-16
**Status:** Approved, ready for plan

## Problem

Today `proxy on/off/status` only toggles the Alibaba ECS instance (the proxy
*server*). The Windows *client*, v2rayN, must still be launched and closed by
hand. The user wants a single command to bring up both ends of the tunnel and
tear them down cleanly.

## Architecture — split by platform

`proxy.ps1` becomes the **orchestrator** (it is the entry point already on the
Windows PATH). It owns all Windows-native concerns: launching v2rayN, graceful
shutdown, and proxy-registry cleanup. These map naturally to PowerShell
(`Start-Process`, `CloseMainWindow()`, `Stop-Process`, registry cmdlets) and are
awkward to drive from Python.

`proxy.py` is unchanged: pure, cross-platform, unit-testable Alibaba-ECS logic.
`proxy.ps1` shells out to it for all server-side actions.

This is the "cleanest split" noted in the original enhancement plan.

## Configuration

- Add `V2RAYN_PATH` to gitignored `.env` and to `.env.example`.
- `proxy.ps1` reads only that one line from `.env` via a simple regex parse.
- Python continues to read the Alibaba vars via `python-dotenv`.
- No hardcoded paths.

## Command flow

### `proxy on`
1. If v2rayN is not already running, `Start-Process` it. v2rayN v7 self-restores
   its last persisted state from `guiNConfig.json` (active Shadowsocks server,
   "China Streaming" routing rules, last sysproxy mode), so no config injection
   is needed. It retries connecting until the server xray is up.
2. `python proxy.py on` to start the ECS instance.

Ordering: launch v2rayN immediately (do not wait for ECS `Running` first). The
client's own retry loop overlaps the ~1-minute ECS boot, so launching first
costs nothing and is simpler.

### `proxy off`
1. Close v2rayN **first**, gracefully, so its exit handler clears the system
   proxy: `CloseMainWindow()` → `Start-Sleep 2` → `Stop-Process -Force` only if
   `!$p.HasExited`.
2. Belt-and-suspenders: reset the proxy registry keys directly regardless.
3. `python proxy.py off` to stop the ECS instance (charging paused).

Ordering: close the client before stopping the server so traffic is never
pointed at a vanishing endpoint.

### `proxy status`
1. `python proxy.py status` (ECS instance state).
2. Report whether the v2rayN process is alive.

## The key risk being mitigated

If v2rayN has system-proxy mode on, it sets registry
`HKCU:\...\Internet Settings\ProxyEnable = 1` and `ProxyServer = 127.0.0.1`. A
hard `Stop-Process` skips v2rayN's exit handler, leaving those keys set → no
internet until fixed by hand. Mitigation is two-layered: graceful close lets
v2rayN clear them itself, and a direct registry reset in `proxy off` guarantees a
clean state even if the graceful path fails.

## Testing

- Existing `client/test_proxy_args.py` (Python arg parsing) stays green —
  `proxy.py` is untouched in behavior.
- PS1 orchestration is verified by running on the real machine:
  - `proxy status` reports both ECS state and v2rayN process state.
  - `proxy on` launches v2rayN and starts the instance.
  - `proxy off` closes v2rayN and stops the instance.
  - After `proxy off`, the `ProxyEnable` registry key is confirmed cleared.

## Out of scope

- No new infrastructure.
- No changes to v2rayN's config or routing.
- No IP-rotation work (tracked separately).
