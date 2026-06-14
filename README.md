# proxy

Routes Chinese streaming traffic through an Alibaba Cloud VPS so the VPS's mainland China IP is presented to streaming sites (Bilibili, iQIYI, Youku, etc.).

---

## Daily Use (TL;DR)

> The day-to-day is just two commands plus a toggle. **You do not need to SSH in or start xray manually** — the `x-ui` service is enabled, so xray + the Shadowsocks inbound auto-start whenever the instance boots.

**Turn ON (to stream):**

1. Start the VPS — xray comes up automatically on boot:
   ```
   proxy on
   ```
   Wait for it to report Running.
2. Open **v2rayN** (run `v2rayN.exe`, or it's already in the system tray). At the bottom of the window confirm:
   - the **Shadowsocks** server row is **active** (double-click it if not)
   - **Routing** dropdown = **China Streaming**
   - **System proxy** dropdown = **Set system proxy**

That's it — open bilibili to confirm.

**Turn OFF (when done):**

1. In v2rayN: **System proxy → Clear system proxy** (so normal browsing isn't routed).
2. Stop the VPS to halt compute billing:
   ```
   proxy off
   ```
   You can leave v2rayN idle in the tray or exit it.

**If the proxy doesn't respond after `proxy on`** (fallback only — not normally needed):

```bash
ssh root@<your-eip>
systemctl status x-ui        # should say: active (running)
x-ui restart                 # if it isn't running
```

First-time setup is in the numbered sections below.

---

## Prerequisites

- Alibaba Cloud ECS instance running **Ubuntu 22.04** in a mainland China region (e.g. cn-hangzhou, cn-shanghai)
- SSH access to the VPS as root or via sudo
- [v2rayN](https://github.com/2dust/v2rayN/releases) on Windows — download the **`v2rayN-windows-64-With-Core.zip`** release (the "With-Core" build bundles xray-core, so you don't need a separate core download). It's portable: extract and run `v2rayN.exe`, no installer. This guide uses the redesigned **v7** UI.

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

> **Why Shadowsocks instead of VLESS + Reality?** We originally tried VLESS + Reality and it **silently failed** — every connection test returned `-1` / TLS errors. The cause: this build of 3x-ui (v3.3.1) ships the new **post-quantum Reality** (mldsa65 / ML-KEM-768), and our v2rayN's bundled xray-core didn't match the server's, so the Reality handshake failed. When a Reality handshake fails, xray doesn't error — it silently forwards you to the camouflage site (e.g. `www.amazon.com`) instead of proxying, which looks exactly like a broken tunnel.
>
> Reality's value is anti-censorship stealth for traffic *leaving* China. Our traffic goes *into* China, so the GFW isn't inspecting it — Reality buys us nothing here. **Shadowsocks is simpler and bulletproof**: just a cipher + password, no SNI, no cert, no handshake params to mismatch. The `deprecated` warning 3x-ui prints for Shadowsocks is harmless; it still works fine.

1. Log in and **immediately change the password** (Panel Settings → change password).
2. Go to **Inbounds → Add Inbound**. On the **Basics** tab:
   - Protocol: `shadowsocks`
   - Port: `443`
   - Method / Cipher: `chacha20-ietf-poly1305` (or `aes-256-gcm`)
   - Security: `none` (Shadowsocks encrypts via its own cipher; do **not** add TLS)
   - Leave the auto-generated password
3. Click **Create**.
4. On the **Inbounds** list, open the inbound's **share / QR** option and copy the **`ss://`** link.

> **Port conflict gotcha:** xray cannot bind port 443 twice. If an old inbound (e.g. a VLESS one) is still on 443, the new Shadowsocks inbound **silently fails to start** and every client test fails identically. **Delete any other inbound on 443 first.** Confirm with `journalctl -u x-ui --no-pager -n 50` — look for `port 443 (tcp) already used by inbound`.

> **3x-ui v3.3.1 note:** This redesigned panel manages **Clients** globally (separate left-sidebar page) and you *attach* them to inbounds. Shadowsocks carries its cipher+password on the inbound itself, so it works from just the steps above. (VLESS/VMess would require creating a client under **Clients** and attaching it to the inbound — the inbound's `Clients` count must show ≥ 1.)

---

## 3. Windows Client Setup (v2rayN v7)

> v2rayN v7 was redesigned — there is **no "Servers" menu**. The big table in the middle **is** the server list.

### Import the server

1. Copy your **`ss://`** link to the clipboard.
2. In v2rayN, click anywhere in the empty server table and press **Ctrl+V** (or **Configuration → Import bulk URL from clipboard**). The server appears as a row.
3. **Double-click** the row (or right-click → **Set as active**) to activate it.

### Add split-tunnel routing

Goal: Chinese streaming domains go **through** the China proxy; everything else stays **direct** (fast, and avoids Google/YouTube being blocked from inside China).

1. **Settings → Routing Setting** → click **➕ Add** to create a new rule set.
2. **Remarks:** `China Streaming`. **Domain strategy:** `IPIfNonMatch`.
3. Click **➕ Add Rule** and create **Rule 1 (must be the top row)**:
   - **outboundTag:** `proxy`
   - **domain:** paste the lines from `client/routing.json` (`domain:bilibili.com`, `domain:iqiyi.com`, `domain:youku.com`, …)
   - leave port / protocol / network blank
4. Click **➕ Add Rule** again for **Rule 2 (below Rule 1)**:
   - **outboundTag:** `direct`
   - **network:** `tcp,udp`
   - leave domain/ip blank (blank = catch-all for everything else)
5. **Rule order is critical** — the `proxy` rule must be **above** the `direct` catch-all, or the catch-all matches everything first and nothing is proxied. Reorder via right-click → Move up if needed.
6. Click **Confirm**.
7. On the main window, set the bottom **Routing** dropdown to **`China Streaming`**, then click **Reload**. **Config changes only apply after Reload.**

### Enable the proxy

At the bottom of v2rayN, set the **System proxy** dropdown to **Set system proxy**. To go fully direct again, set it back to **Clear system proxy**.

---

## 4. Verify

> **Ignore the `Delay (ms)` column and the "real delay" test — they will always show `-1` for a China server.** v2rayN tests latency against Google, which is blocked from inside mainland China, so the test fails even when the proxy works perfectly. This single red herring cost hours of debugging. Verify with the commands below instead.

Test the **split tunnel** directly through v2rayN's local SOCKS proxy (port 10808). In PowerShell (`curl` is an alias for `Invoke-WebRequest` — use `curl.exe`):

```powershell
# A site NOT in the proxy list -> should show YOUR real IP (direct):
curl.exe --proxy socks5h://127.0.0.1:10808 https://ipinfo.io/ip

# A Chinese streaming domain -> Bilibili's region API reports the IP it sees.
# Should report the VPS: addr 120.26.202.101, country 中国, country_code 86:
curl.exe --proxy socks5h://127.0.0.1:10808 "https://api.bilibili.com/x/web-interface/zone"
```

- The first command should return your **real/home IP** (routed direct).
- The second should report **中国 / country_code 86** with the VPS's IP — proof that streaming domains exit through China.

Then open [bilibili.com](https://bilibili.com) with system proxy on and confirm region-locked content plays.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Panel says **page not found** / `/xui` 404s | The path is the random secret base URI, not `/xui`. Run `x-ui settings` and use the `webBasePath` value: `http://<eip>:<port>/<webBasePath>/` |
| **admin/admin rejected** ("invalid username or password") | Credentials are randomized at install. Run `x-ui` → choose **Reset Username & Password**, then log in with the new values |
| Panel URL unreachable (connection refused/timeout) | Check Alibaba Security Group allows the panel port (2053) inbound, **and** `ufw status` on the VPS lists `2053/tcp`. Confirm `systemctl status x-ui` shows `active (running)` |
| Install hangs on **"Installing acme.sh for SSL"** | acme.sh downloads from GitHub (blocked in China). Press **Ctrl+C**, rerun `sudo bash install.sh`, and choose **`4` (Skip SSL)** at the SSL prompt |
| `Downloading x-ui failed ... access GitHub` | China region intermittently blocks GitHub. Retry the install; if persistent, replace the system disk and try again |
| **REMOTE HOST IDENTIFICATION HAS CHANGED** on ssh/scp | The VPS key changed (e.g. after disk reinit). Run `ssh-keygen -R <your-eip>` and retry |
| `ssh`/`scp` **times out** | Use the Alibaba Cloud **Workbench** browser terminal (Instance → Remote Connection) and its upload-file button instead |
| Accidentally set a **random panel port** | Run `x-ui settings` to see the current port, or rerun `sudo bash install.sh` and answer `y` → `2053` at the port prompt |
| **Delay column / "real delay" test shows `-1`** | **Expected — ignore it.** v2rayN tests against Google, which is blocked from China. It says `-1` even when the proxy works. Verify with the `curl.exe --proxy socks5h://...` commands in §4 instead. |
| Client connects but **every test fails** (`-1`, TLS error, empty reply) the same way across protocols | Likely a **port 443 conflict** — another inbound is holding 443 so your new one never started. Delete the other inbound; check `journalctl -u x-ui -n 50` for `port 443 (tcp) already used`. |
| **VLESS + Reality** won't connect; traffic seems to hit the camouflage site | Reality version mismatch between this 3x-ui (post-quantum Reality) and v2rayN's xray-core. Switch the inbound to **Shadowsocks** (see §2). |
| **Streaming domain still shows your real IP** in `api.bilibili.com/.../zone` | Routing **rule order** — the `direct` catch-all is above the `proxy` rule. Put the `proxy` rule on top, **Confirm**, then **Reload**. Changes don't apply until Reload. |
| Non-streaming sites are slow / Google & YouTube blocked | You're on **Global** routing (everything through China). Switch the Routing dropdown to your **China Streaming** split-tunnel rule set. |
| v2rayN shows connection error | Verify the `ss://` share link is correct; check VPS firewall + Alibaba security group allow port 443 |
| IP check returns your real IP for a streaming site | Ensure system proxy is set, the right server is **active**, and the domain is in your proxy routing rule (`client/routing.json`) |
| Streaming site still geo-blocked | Check the domain is in `client/routing.json` and in your v2rayN proxy rule; add it if missing, then **Reload** |

---

## 5. CLI Toggle (Start / Stop the VPS)

Install dependencies once:

```bash
pip install -r client/requirements.txt
```

Copy the credential template and fill in your values:

**Bash:**
```bash
cp client/.env.example client/.env
```

**PowerShell:**
```powershell
Copy-Item client\.env.example client\.env
```

Then edit `client/.env` — get your Access Key from Alibaba Cloud console → RAM → Access Keys.

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
proxy on       # Start the VPS — prints the EIP when ready
proxy off      # Stop the VPS in economical mode (no compute charges)
proxy status   # Show current instance state
```

> After `proxy off`, disable the system proxy in v2rayN: tray icon → System proxy → Clear system proxy.

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
- Requires updating the server address (the new IP) in the `ss://` link / v2rayN server afterward

**Option C — Multiple VPS instances**
- Run 3x-ui on 2–3 cheap ECS instances in different zones (each gets a different IP)
- Swap the active server in v2rayN to rotate manually
