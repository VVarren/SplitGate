# SplitGate

**A one-command, split-tunnel gateway for region-locked Chinese streaming.**

**ALWAYS USE "proxy off" BEFORE SHUTTING OFF THE TERMINAL**

SplitGate routes traffic for Chinese streaming sites (Bilibili, iQIYI, Youku, Tencent Video, …) through a mainland-China VPS, while everything else goes direct. A single command brings the whole tunnel up and down — it starts/stops the cloud VPS *and* runs the local proxy engine headlessly, with no GUI to babysit.

```
proxy on      # tunnel up:   start VPS + launch xray (hidden) + set system proxy
proxy off     # tunnel down:  clear proxy + stop xray + stop VPS (pauses billing)
proxy status  # show state
```

---

## Why

Streaming catalogs like Bilibili's anime dubs/subs are geo-locked to mainland China. A normal VPN sends *all* your traffic abroad — slow, and it trips Google/YouTube blocks that apply from inside China. SplitGate instead:

- **Split-tunnels by domain** — only Chinese streaming domains exit through China; everything else stays on your real connection at full speed (~0 ms overhead on non-proxied traffic).
- **Runs headless** — the proxy engine (`xray`) runs as a hidden background process. No tray apps, no manual GUI clicks.
- **Pauses billing when off** — `proxy off` stops the ECS instance in a mode that halts compute charges, so an idle proxy costs almost nothing.
- **Keeps secrets out of the repo** — all credentials live in a gitignored `.env`; the committed config is a placeholder template.

---

## How it works

```
  proxy on / off / status            (PowerShell CLI, Windows)
        │
        ├─► proxy.py ───────────────► Alibaba Cloud ECS
        │   (ECS SDK)                 ├─ start / stop instance (StopCharging = no compute billing)
        │                             └─ 3x-ui · xray · Shadowsocks inbound  (:443)
        │
        └─► xray.ps1
              ├─ render xray config from .env + template
              ├─ launch xray.exe  ──hidden──►  127.0.0.1:10808  (SOCKS + HTTP)
              └─ set Windows system proxy

  Browser / apps ─► 127.0.0.1:10808 ─► xray split-tunnel router:
        • Chinese streaming domains ─► Shadowsocks ─► China VPS ─► site   (China IP)
        • everything else ──────────► direct                              (your real IP)
```

The Windows client is just the open-source `xray-core` engine plus two small scripts. `xray.ps1` renders a complete config (server details + split-tunnel routing) from your `.env` and a template, then runs `xray.exe` hidden and toggles the Windows system-proxy registry. `proxy.py` independently starts/stops the cloud VPS. One `proxy on` orchestrates both.

**Why Shadowsocks (not VLESS + Reality)?** Reality's stealth is for traffic *leaving* a censored network; SplitGate's traffic goes *into* China, where the GFW isn't inspecting it — so Reality adds fragile handshake parameters for zero benefit. Shadowsocks is just a cipher + password: simple and reliable for this use case.

---

## Tech stack

| Layer | Tech |
|---|---|
| Cloud VPS | Alibaba Cloud ECS (mainland China region), Ubuntu 22.04 |
| Server proxy | [3x-ui](https://github.com/MHSanaei/3x-ui) panel · [xray-core](https://github.com/XTLS/Xray-core) · Shadowsocks (`chacha20-ietf-poly1305`) |
| Windows client | `xray-core` (bundled with [v2rayN](https://github.com/2dust/v2rayN)) driven headlessly by PowerShell |
| Orchestration | PowerShell (`xray.ps1`) + Python (`proxy.py`, Alibaba ECS SDK) |
| Tests | Pester (PowerShell) · pytest (Python) |

---

## Repository layout

```
client/
  proxy.ps1                  thin entry point → dispatches on/off/status
  xray.ps1                   headless xray: render config, run hidden, manage system proxy
  xray-config.template.json  xray config template (placeholders + split-tunnel routing)
  routing.json               human-readable list of proxied domains (kept in sync with template)
  proxy.py                   Alibaba ECS start/stop/status (StopCharging billing pause)
  .env.example               credential/config template — copy to .env and fill in
  xray.Tests.ps1             Pester tests for the client
  test_proxy_args.py         pytest tests for proxy.py
server/
  install.sh                 installs 3x-ui on the VPS, opens firewall ports
```

Runtime artifacts (rendered config, pidfile, logs) are written to `client/.xray/` and are gitignored.

---

## Quick start

Already set up? Daily use is three commands:

```
proxy on       # render config, start the VPS, launch xray hidden, set system proxy
proxy off      # clear system proxy, kill xray, stop the VPS (no compute charges)
proxy status   # VPS state + whether xray (or a stray v2rayN GUI) is running
```

First-time setup is below: **(1)** provision the VPS, **(2)** add a Shadowsocks inbound, **(3)** point the client at the `xray` binary, **(5)** fill in `.env` and add the CLI to PATH.

---

## 1. VPS setup

You need an Alibaba Cloud ECS instance running **Ubuntu 22.04** in a mainland-China region (e.g. `cn-hangzhou`), with SSH access and a security group allowing inbound TCP **2053** (panel) and **443** (proxy).

> **Mainland-China note:** GitHub is frequently blocked or throttled from China-region VPS instances, and the 3x-ui installer downloads from GitHub. If it fails with `Downloading x-ui failed ... access GitHub`, just retry — access is intermittent. The **SSL step is the most common hang** (it fetches `acme.sh` from GitHub), which is why we skip it.

Copy the installer to the VPS and run it:

```powershell
scp server\install.sh root@<your-eip>:~/install.sh
ssh root@<your-eip>
```

```bash
sudo bash install.sh
```

The installer is interactive — answer the prompts like this:

| Prompt | Answer | Why |
|---|---|---|
| Database Selection | `1` (SQLite) | Fine for personal use |
| Customize panel port? | `y`, then `2053` | Must match the security group rule (else a **random** port is assigned) |
| SSL Certificate Setup | `4` (Skip SSL) | acme.sh downloads from GitHub (blocked in China) and needs port 80; the random base path already protects the panel |
| IPv6 address | *(press Enter)* | ECS has no IPv6 by default |

The installer assigns a **random username, password, and secret base URI path** (not `admin`/`admin` or `/xui`). Retrieve them with:

```bash
x-ui settings        # prints port + webBasePath
```

Your panel URL is `http://<your-eip>:<port>/<webBasePath>/` (e.g. `http://203.0.113.10:2053/BPUx631aUVc7A7b36R/`). If credentials are rejected, run `x-ui` → **Reset Username & Password**.

> **Reset/relocate gotchas:** after a disk reinit, SSH may fail with *REMOTE HOST IDENTIFICATION HAS CHANGED* — run `ssh-keygen -R <your-eip>`. If `ssh`/`scp` times out, use the Alibaba Cloud **Workbench** browser terminal (Instance → Remote Connection) and its upload button.

---

## 2. Add a Shadowsocks inbound (3x-ui)

1. Log in and **change the panel password** (Panel Settings).
2. **Inbounds → Add Inbound**, on the **Basics** tab:
   - Protocol: `shadowsocks`
   - Port: `443`
   - Method / Cipher: `chacha20-ietf-poly1305`
   - Security: `none` (Shadowsocks brings its own cipher — do **not** add TLS)
   - Leave the auto-generated password
3. **Create.**
4. Note the **cipher** and **password** — they go into `client/.env` as `SS_CIPHER` and `SS_PASSWORD` (you can re-open the inbound any time to read them back).

> **Port-443 conflict:** xray can't bind 443 twice. If another inbound (e.g. an old VLESS one) holds 443, the Shadowsocks inbound **silently fails to start** and every client test fails identically. Delete the other inbound; confirm with `journalctl -u x-ui --no-pager -n 50` (look for `port 443 (tcp) already used`).

---

## 3. Windows client — get the `xray` binary

There is **no GUI to configure**. The client only needs the `xray-core` binary, which ships inside the v2rayN release.

1. Download **`v2rayN-windows-64-With-Core.zip`** from [v2rayN releases](https://github.com/2dust/v2rayN/releases) and extract it somewhere stable.
2. Note the path to **`bin\xray\xray.exe`** — this goes in `.env` as `XRAY_EXE`. You never launch `v2rayN.exe`.

The split-tunnel routing (Chinese streaming → proxy, everything else → direct) is baked into `client/xray-config.template.json`. The human-readable domain list lives in `client/routing.json`. To proxy an additional site, add its `domain:` entry to the `dns` and `routing` lists in the template (and mirror it in `routing.json`); it applies on the next `proxy on`.

---

## 4. Verify

After `proxy on`, test the split tunnel through the local SOCKS proxy. In PowerShell use `curl.exe` (plain `curl` is an alias for `Invoke-WebRequest`):

```powershell
# Not in the proxy list -> should show YOUR real IP (direct):
curl.exe --proxy socks5h://127.0.0.1:10808 https://ipinfo.io/ip

# A Chinese streaming domain -> Bilibili's region API reports the IP it sees.
# Should report country 中国, country_code 86:
curl.exe --proxy socks5h://127.0.0.1:10808 "https://api.bilibili.com/x/web-interface/zone"
```

The first returns your real/home IP; the second reports **中国 / country_code 86** with the VPS's IP — proof that streaming domains exit through China. Then open [bilibili.com](https://bilibili.com) and confirm region-locked content plays.

> Don't loop requests against `api.bilibili.com` — repeated automated hits risk an IP ban. A couple of checks is plenty.

---

## 5. CLI setup

Install Python dependencies once:

```bash
pip install -r client/requirements.txt
```

Copy the template and fill in your values:

```powershell
Copy-Item client\.env.example client\.env
```

| Variable | Value |
|---|---|
| `ALIBABA_ACCESS_KEY_ID` / `ALIBABA_ACCESS_KEY_SECRET` | Alibaba Cloud console → RAM → Access Keys |
| `ALIBABA_INSTANCE_ID` | Your ECS instance ID (e.g. `i-bp1…`) |
| `ALIBABA_REGION` | e.g. `cn-hangzhou` |
| `PROXY_EIP` | VPS IP (used for the "connect via" message) |
| `SERVER_HOST` | The IP the client connects to — your VPS's stable Elastic IP |
| `SS_PASSWORD` | Shadowsocks password from the inbound (§2) |
| `SS_PORT` | `443` |
| `SS_CIPHER` | `chacha20-ietf-poly1305` |
| `SOCKS_PORT` | `10808` |
| `XRAY_EXE` | Full path to the bundled `xray.exe` (e.g. `…\v2rayN-windows-64\bin\xray\xray.exe`) |

Add `client/` to your Windows PATH so `proxy` works from any terminal. In an **admin** PowerShell:

```powershell
[Environment]::SetEnvironmentVariable('PATH', [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';C:\path\to\SplitGate\client', [EnvironmentVariableTarget]::Machine)
```

Open a new terminal, then use `proxy on` / `off` / `status`.

> Client orchestration lives in `client/xray.ps1` (Pester-tested via `client/xray.Tests.ps1`); `proxy.py` handles the ECS side (pytest via `client/test_proxy_args.py`).

---

## Running the tests

```powershell
Invoke-Pester client/xray.Tests.ps1     # PowerShell client logic
python -m pytest client/                # proxy.py argument handling
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `proxy on` → **xray exited immediately … invalid character looking for beginning of value** | A malformed rendered config. Inspect `client/.xray/config.json` and `client/.xray/xray.log`. (A UTF-8 BOM was a known cause and is fixed in current code.) |
| `proxy on` → **xray exited immediately** (port in use) | Something holds `10808` — usually the **v2rayN GUI**; close it (`Get-Process v2rayN`). `proxy status` warns about this. Also check for a stray `xray` (`Get-Process xray`). |
| **Streaming domain still shows your real IP** in the bilibili zone API | The domain isn't in the proxy list. Add its `domain:` entry to `client/xray-config.template.json` (dns + routing), then re-run `proxy on`. |
| `proxy on` → **Missing env vars: …** | A required key is missing from `client/.env`. Compare with `client/.env.example`. |
| Internet broken after a crash / hard kill | Reset the system proxy: `Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyEnable -Value 0`. (`proxy off` does this automatically.) |
| Panel **page not found** / `/xui` 404 | The path is the random secret base URI. Run `x-ui settings` and use the `webBasePath`. |
| Panel **admin/admin rejected** | Credentials are randomized at install. Run `x-ui` → **Reset Username & Password**. |
| Panel unreachable (refused/timeout) | Security group must allow the panel port (2053) inbound; `ufw status` on the VPS should list `2053/tcp`; `systemctl status x-ui` should be `active (running)`. |
| Install hangs on **"Installing acme.sh for SSL"** | acme.sh downloads from GitHub (blocked in China). **Ctrl+C**, rerun `sudo bash install.sh`, choose **`4` (Skip SSL)**. |
| **Client connects but every test fails identically** | Likely a **port 443 conflict** on the VPS — another inbound holds 443. Delete it; check `journalctl -u x-ui -n 50`. |

---

## Other platforms

The same VPS and Shadowsocks inbound work for any client — no server changes needed. Export the `ss://` share link from 3x-ui and import it into e.g. [NekoRay](https://github.com/MatsuriDayo/nekoray)/[Hiddify](https://github.com/hiddify/hiddify-app) (Linux), or [Shadowrocket](https://apps.apple.com/app/shadowrocket/id932747118)/[Streisand](https://apps.apple.com/app/streisand/id6450534064) (iOS). Recreate the same split-tunnel routing (Chinese streaming → proxy, else → direct) on each.

---

## IP rotation (optional)

The VPS has a fixed Elastic IP, so the destination always sees the same address. If you need rotation:

- **NAT Gateway + EIP pool** — attach a NAT Gateway with 3–5 EIPs in the SNAT pool; Alibaba rotates the outbound EIP automatically, no client changes.
- **Manual EIP swap** — release/allocate a new EIP in the console, then update `SERVER_HOST` in `client/.env`.
- **Multiple instances** — run 3x-ui on several cheap instances in different zones and swap `SERVER_HOST`.

---

## Disclaimer

Provided as-is for personal and educational use. You are responsible for complying with the terms of service of any sites you access and with all applicable laws in your jurisdiction. This project does not bypass authentication or payment — it only changes the network path of your own traffic.
