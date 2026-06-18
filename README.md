# proxy

Routes Chinese streaming traffic through an Alibaba Cloud VPS so the VPS's mainland China IP is presented to streaming sites (Bilibili, iQIYI, Youku, etc.).

The Windows client runs **headless**: `proxy on` drives `xray.exe` directly as a hidden background process — the v2rayN GUI is never opened.

---

## Daily Use (TL;DR)

> One command runs both ends of the tunnel. `proxy on/off/status` manages **both** the China VPS **and** the local headless xray process — no GUI, no manual SSH. The `x-ui` service is enabled on the VPS, so xray + the Shadowsocks inbound auto-start whenever the instance boots.

**Turn ON (to stream):**

```
proxy on
```

This renders the xray config from `client/.env`, starts the VPS, launches `xray.exe` hidden (SOCKS/HTTP on `127.0.0.1:10808`), and sets the Windows system proxy. No window appears. When it reports the PID and "System proxy set", open bilibili to confirm.

**Turn OFF (when done):**

```
proxy off
```

This clears the system-proxy registry key, kills the hidden xray process, then stops the VPS to halt compute billing.

**Check state:**

```
proxy status
```

Reports the VPS instance state, whether xray is running, and warns if the v2rayN GUI is also running (it would contend for port 10808).

> **One-time setup:** fill in `client/.env` (see §5), including `XRAY_EXE` (path to the bundled `xray.exe`) and the Shadowsocks `SS_PASSWORD`. Without these, `proxy on` cannot start the tunnel.

**If the proxy doesn't respond after `proxy on`** (fallback only — not normally needed):

```bash
ssh root@<your-eip>
systemctl status x-ui        # should say: active (running)
x-ui restart                 # if it isn't running
```

Also check `client/.xray/xray.log` locally for client-side startup errors.

First-time setup is in the numbered sections below.

---

## Prerequisites

- Alibaba Cloud ECS instance running **Ubuntu 22.04** in a mainland China region (e.g. cn-hangzhou, cn-shanghai)
- SSH access to the VPS as root or via sudo
- [v2rayN](https://github.com/2dust/v2rayN/releases) on Windows — download the **`v2rayN-windows-64-With-Core.zip`** release. We **only use the bundled `xray.exe`** (`bin\xray\xray.exe`) and its geo data; the GUI is never launched. It's portable: just extract the zip somewhere stable.

---

## 1. VPS Setup

> **Mainland China note:** GitHub is frequently blocked or throttled from China-region VPS instances. The 3x-ui installer downloads from GitHub, so it may fail with `Downloading x-ui failed, please be sure that your server can access GitHub`. If that happens, just retry — access is often intermittent. The **SSL step is the most common hang** (it downloads `acme.sh` from GitHub), which is why we skip it below.

First, copy `server/install.sh` to your VPS. From PowerShell:

```powershell
scp server\install.sh root@<your-eip>:~/install.sh
```

> If you reinitialized the disk and `scp`/`ssh` fails with **REMOTE HOST IDENTIFICATION HAS CHANGED**, clear the stale key first: `ssh-keygen -R <your-eip>`, then retry.
>
> If `scp`/`ssh` **times out**, connect through the Alibaba Cloud console instead: **Instance → Remote Connection → Workbench** (browser terminal), and upload `install.sh` using the Workbench upload-file button.

Then SSH into the VPS:

```powershell
ssh root@<your-eip>
```

Once connected (you are now in a Linux terminal on the VPS), run:

```bash
sudo bash install.sh
```

**The installer is interactive.** Answer the prompts exactly like this:

| Prompt | Answer | Why |
|---|---|---|
| Database Selection | `1` (SQLite) | Fine for personal use |
| Customize panel port? | `y`, then `2053` | Must match the security group rule. Answering `n` assigns a **random** port. |
| SSL Certificate Setup | `4` (Skip SSL) | acme.sh downloads from GitHub (blocked in China) and needs port 80. The secret base path already protects the panel. |
| IPv6 address | *(press Enter)* | ECS has no IPv6 by default |

The installer sets a **random username, password, and secret base URI path** — it does **not** use `admin`/`admin` or `/xui`. Retrieve them after install:

```bash
x-ui settings
```

This prints the `port` and `webBasePath`. Your panel URL is:

```
http://<your-eip>:<port>/<webBasePath>/
```

For example: `http://120.26.202.101:2053/BPUx631aUVc7A7b36R/`

If you don't know the username/password (or they're rejected), reset them by running `x-ui` to open the management menu and choosing the **Reset Username & Password** option, then log in with the new values.

Open the panel URL in your browser.

---

## 2. Configure 3x-ui (Shadowsocks Inbound)

> **Why Shadowsocks instead of VLESS + Reality?** We originally tried VLESS + Reality and it **silently failed** — every connection test returned `-1` / TLS errors. The cause: this build of 3x-ui (v3.3.1) ships the new **post-quantum Reality** (mldsa65 / ML-KEM-768), and our xray-core didn't match the server's, so the Reality handshake failed. When a Reality handshake fails, xray doesn't error — it silently forwards you to the camouflage site (e.g. `www.amazon.com`) instead of proxying, which looks exactly like a broken tunnel.
>
> Reality's value is anti-censorship stealth for traffic *leaving* China. Our traffic goes *into* China, so the GFW isn't inspecting it — Reality buys us nothing here. **Shadowsocks is simpler and bulletproof**: just a cipher + password, no SNI, no cert, no handshake params to mismatch. The `deprecated` warning 3x-ui prints for Shadowsocks is harmless; it still works fine.

1. Log in and **immediately change the password** (Panel Settings → change password).
2. Go to **Inbounds → Add Inbound**. On the **Basics** tab:
   - Protocol: `shadowsocks`
   - Port: `443`
   - Method / Cipher: `chacha20-ietf-poly1305`
   - Security: `none` (Shadowsocks encrypts via its own cipher; do **not** add TLS)
   - Leave the auto-generated password
3. Click **Create**.
4. **Note the cipher and password** — you'll put them in `client/.env` (§5) as `SS_CIPHER` and `SS_PASSWORD`. (You can re-open the inbound any time to read them back.)

> **Port conflict gotcha:** xray cannot bind port 443 twice. If an old inbound (e.g. a VLESS one) is still on 443, the new Shadowsocks inbound **silently fails to start** and every client test fails identically. **Delete any other inbound on 443 first.** Confirm with `journalctl -u x-ui --no-pager -n 50` — look for `port 443 (tcp) already used by inbound`.

---

## 3. Windows Client Setup (headless xray)

There is **no GUI to configure**. The client is driven entirely by `client/xray.ps1`, which renders a complete xray config (server + split-tunnel routing) from a template and your `.env`, then runs the bundled `xray.exe` hidden.

### Get the xray binary

1. Extract `v2rayN-windows-64-With-Core.zip` to a stable location (e.g. `C:\Users\you\Downloads\v2rayN-windows-64`).
2. Note the path to **`bin\xray\xray.exe`** inside it — this goes in `.env` as `XRAY_EXE`. You never run `v2rayN.exe`.

### Split-tunnel routing (already built in)

The routing — Chinese streaming domains go **through** the China proxy, everything else stays **direct** (fast, and avoids Google/YouTube being blocked from inside China) — is baked into `client/xray-config.template.json`. The human-readable list of proxied domains lives in `client/routing.json`; the two are kept in sync.

To proxy an additional site, add its `domain:` entry to **both** the `dns` and `routing` domain lists in `client/xray-config.template.json` (and mirror it into `client/routing.json` for the record). Changes take effect on the next `proxy on`.

Continue to §5 to fill in `.env` and run the tunnel.

---

## 4. Verify

After `proxy on`, test the **split tunnel** directly through the local SOCKS proxy (port 10808). In PowerShell (`curl` is an alias for `Invoke-WebRequest` — use `curl.exe`):

```powershell
# A site NOT in the proxy list -> should show YOUR real IP (direct):
curl.exe --proxy socks5h://127.0.0.1:10808 https://ipinfo.io/ip

# A Chinese streaming domain -> Bilibili's region API reports the IP it sees.
# Should report the VPS: country 中国, country_code 86:
curl.exe --proxy socks5h://127.0.0.1:10808 "https://api.bilibili.com/x/web-interface/zone"
```

- The first command should return your **real/home IP** (routed direct).
- The second should report **中国 / country_code 86** with the VPS's IP — proof that streaming domains exit through China.

Then open [bilibili.com](https://bilibili.com) with the proxy on and confirm region-locked content plays.

> Don't hammer `api.bilibili.com` in a loop — repeated automated hits risk an IP ban. A couple of checks is plenty.

---

## 5. CLI Toggle (Start / Stop the tunnel)

Install Python dependencies once:

```bash
pip install -r client/requirements.txt
```

Copy the credential template and fill in your values:

**PowerShell:**
```powershell
Copy-Item client\.env.example client\.env
```

Then edit `client/.env`:

| Variable | Value |
|---|---|
| `ALIBABA_ACCESS_KEY_ID` / `ALIBABA_ACCESS_KEY_SECRET` | From Alibaba Cloud console → RAM → Access Keys |
| `ALIBABA_INSTANCE_ID` | Your ECS instance ID (e.g. `i-bp1...`) |
| `ALIBABA_REGION` | e.g. `cn-hangzhou` |
| `PROXY_EIP` | The VPS IP (used for the "connect via" message) |
| `SERVER_HOST` | The IP the client connects to — your VPS's stable Elastic IP |
| `SS_PASSWORD` | Shadowsocks password from the 3x-ui inbound (§2) |
| `SS_PORT` | `443` |
| `SS_CIPHER` | `chacha20-ietf-poly1305` |
| `SOCKS_PORT` | `10808` |
| `XRAY_EXE` | Full path to the bundled `xray.exe`, e.g. `C:\Users\you\Downloads\v2rayN-windows-64\bin\xray\xray.exe` |

Add `client/` to your Windows PATH permanently (one-time setup):

1. Press **Win** → type `powershell` → right-click **Windows PowerShell** → **Run as administrator**
2. Paste and press Enter:

```powershell
[Environment]::SetEnvironmentVariable('PATH', [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';C:\dev\Personal\proxy\client', [EnvironmentVariableTarget]::Machine)
```

3. Close the admin window — no output means it worked
4. Open a **new** terminal (the change won't apply to already-open windows)

Then:

```
proxy on       # Render config, start the VPS, launch xray hidden, set system proxy
proxy off      # Clear the system proxy, kill xray, stop the VPS (no compute charges)
proxy status   # Show instance state + whether xray (and any stray v2rayN GUI) is running
```

> The Windows orchestration lives in `client/xray.ps1` (unit-tested via `client/xray.Tests.ps1`, 21 Pester tests); `proxy.py` handles the Alibaba ECS side (tested via `client/test_proxy_args.py`). Runtime artifacts — the rendered config, pidfile, and logs — are written to `client/.xray/` (gitignored).

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `proxy on` → **xray exited immediately. Log tail: ... invalid character looking for beginning of value** | The rendered config had a UTF-8 BOM (fixed in current code). If you see other parse errors, inspect `client/.xray/config.json` and `client/.xray/xray.log`. |
| `proxy on` → **xray exited immediately** (port in use) | Something else holds `10808`. Most often the **v2rayN GUI** is still running — close it (`Get-Process v2rayN`); `proxy status` warns about this. Also check for a stray earlier `xray` (`Get-Process xray`). |
| **Streaming domain still shows your real IP** in `api.bilibili.com/.../zone` | The domain isn't in the proxy routing list. Add its `domain:` entry to `client/xray-config.template.json` (dns + routing lists), then re-run `proxy on`. |
| `proxy on` → **Missing env vars: ...** | A required key is absent from `client/.env`. Compare against `client/.env.example` and §5. |
| `proxy on` → **xray.exe path** errors | `XRAY_EXE` in `.env` doesn't point at a real `bin\xray\xray.exe`. Fix the path. |
| Internet broken after a hard kill / crash | Reset the system proxy: `Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyEnable -Value 0`. (`proxy off` does this automatically.) |
| Panel says **page not found** / `/xui` 404s | The path is the random secret base URI, not `/xui`. Run `x-ui settings` and use the `webBasePath` value: `http://<eip>:<port>/<webBasePath>/` |
| **admin/admin rejected** ("invalid username or password") | Credentials are randomized at install. Run `x-ui` → choose **Reset Username & Password**, then log in with the new values |
| Panel URL unreachable (connection refused/timeout) | Check Alibaba Security Group allows the panel port (2053) inbound, **and** `ufw status` on the VPS lists `2053/tcp`. Confirm `systemctl status x-ui` shows `active (running)` |
| Install hangs on **"Installing acme.sh for SSL"** | acme.sh downloads from GitHub (blocked in China). Press **Ctrl+C**, rerun `sudo bash install.sh`, and choose **`4` (Skip SSL)** at the SSL prompt |
| `Downloading x-ui failed ... access GitHub` | China region intermittently blocks GitHub. Retry the install; if persistent, replace the system disk and try again |
| **REMOTE HOST IDENTIFICATION HAS CHANGED** on ssh/scp | The VPS key changed (e.g. after disk reinit). Run `ssh-keygen -R <your-eip>` and retry |
| `ssh`/`scp` **times out** | Use the Alibaba Cloud **Workbench** browser terminal (Instance → Remote Connection) and its upload-file button instead |
| Client connects but **every test fails** the same way | Likely a **port 443 conflict** on the VPS — another inbound is holding 443 so your Shadowsocks one never started. Delete the other inbound; check `journalctl -u x-ui -n 50` for `port 443 (tcp) already used`. |

---

## Future Clients

The same VPS and Shadowsocks inbound works for all platforms — no server changes needed.

| Platform | Client |
|---|---|
| Linux | [NekoRay](https://github.com/MatsuriDayo/nekoray) or [Hiddify](https://github.com/hiddify/hiddify-app) |
| iOS | [Shadowrocket](https://apps.apple.com/app/shadowrocket/id932747118) or [Streisand](https://apps.apple.com/app/streisand/id6450534064) |

All support the `ss://` Shadowsocks share link exported from 3x-ui. Recreate the same split-tunnel routing (Chinese streaming domains → proxy, everything else → direct) on each client.

---

## IP Rotation (Optional)

The VPS has a fixed Elastic IP (EIP), so Bilibili always sees the same IP. For normal streaming this is fine. If you ever need IP rotation:

**Option A — NAT Gateway + EIP pool (recommended)**
- Attach an Alibaba Cloud NAT Gateway to the VPS's VPC
- Add 3–5 EIPs to the SNAT pool
- Alibaba Cloud rotates which EIP is used for outbound traffic automatically
- No client config changes needed; Bilibili sees a different IP per session
- Cost: ~¥0.015/hr per EIP + NAT Gateway hourly fee

**Option B — EIP swap (manual, free)**
- In the Alibaba Cloud console: release the current EIP, allocate a new one, re-attach it
- New IP immediately, same server and 3x-ui config
- Requires updating `SERVER_HOST` in `client/.env` to the new IP afterward

**Option C — Multiple VPS instances**
- Run 3x-ui on 2–3 cheap ECS instances in different zones (each gets a different IP)
- Swap `SERVER_HOST` in `client/.env` to rotate manually
