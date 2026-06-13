# proxy

Routes Chinese streaming traffic through an Alibaba Cloud VPS so the VPS's mainland China IP is presented to streaming sites (Bilibili, iQIYI, Youku, etc.).

## Prerequisites

- Alibaba Cloud ECS instance running **Ubuntu 22.04** in a mainland China region (e.g. cn-hangzhou, cn-shanghai)
- SSH access to the VPS as root or via sudo
- [v2rayN](https://github.com/2dust/v2rayN/releases) installed on Windows (download the `v2rayN-windows-64.zip` release)

---

## 1. VPS Setup

First, copy `server/install.sh` to your VPS. From PowerShell:

```powershell
scp server\install.sh root@<your-eip>:~/install.sh
```

Then SSH into the VPS:

```powershell
ssh root@<your-eip>
```

Once connected (you are now in a Linux terminal on the VPS), run:

```bash
sudo bash install.sh
```

When it finishes it prints:

```
Panel URL : http://<your-vps-ip>:2053/xui
Username  : admin
Password  : admin
```

Open that URL in your browser.

---

## 2. Configure 3x-ui (VLESS Inbound)

1. Log in and **immediately change the default password** (Settings → Panel settings → Change password)
2. Go to **Inbounds → Add Inbound**
3. Set the following:
   - Protocol: `vless`
   - Port: `443`
   - Transmission: `TCP`
   - Security: `TLS` (3x-ui generates a self-signed cert automatically)
   - Flow: `xtls-rprx-vision` (optional but improves performance)
4. Click **Add** to save
5. In the inbounds list, click the **QR / Share** icon on your new inbound
6. Copy the `vless://` share link

---

## 3. Windows Client Setup (v2rayN)

### Import the server

1. Open v2rayN
2. Click **Servers → Add server from clipboard** and paste the `vless://` link
3. The server appears in the list — right-click it and set as **Active server**

### Import routing rules

1. Go to **Settings → Routing settings**
2. Click **Custom routing rules** → **Import from file**
3. Select `client/routing.json` from this repository
4. Click **Save**

### Enable the proxy

1. In the v2rayN tray icon menu, set **System proxy → Set as system proxy**
2. The tray icon turns blue when active

---

## 4. Verify

Open a terminal and run:

**Bash:**
```bash
curl --proxy socks5://127.0.0.1:10808 https://api.ip.sb/ip
```

**PowerShell** (`curl` in PowerShell is an alias for `Invoke-WebRequest` — use `curl.exe` instead):
```powershell
curl.exe --proxy socks5://127.0.0.1:10808 https://api.ip.sb/ip
```

The returned IP should be your Alibaba VPS's Chinese IP address.

Then open [bilibili.com](https://bilibili.com) and confirm region-locked content is accessible.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Panel URL unreachable | Check Alibaba Security Group allows port 2053 inbound |
| v2rayN shows connection error | Verify the share link is correct; check VPS firewall allows port 443 |
| IP check returns your real IP | Ensure system proxy is enabled in v2rayN tray icon |
| Streaming site still geo-blocked | Check the domain is in `client/routing.json`; add it if missing |

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

The same VPS and inbound works for all platforms — no server changes needed.

| Platform | Client |
|---|---|
| Linux | [NekoRay](https://github.com/MatsuriDayo/nekoray) or [Hiddify](https://github.com/hiddify/hiddify-app) |
| iOS | [Shadowrocket](https://apps.apple.com/app/shadowrocket/id932747118) or [Streisand](https://apps.apple.com/app/streisand/id6450534064) |

Both support VLESS share links exported from 3x-ui.

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
- Requires updating the `vless://` share link in v2rayN afterward

**Option C — Multiple VPS instances**
- Run 3x-ui on 2–3 cheap ECS instances in different zones (each gets a different IP)
- Swap the active server in v2rayN to rotate manually
