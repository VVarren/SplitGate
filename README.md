# proxy

Routes Chinese streaming traffic through an Alibaba Cloud VPS so the VPS's mainland China IP is presented to streaming sites (Bilibili, iQIYI, Youku, etc.).

## Prerequisites

- Alibaba Cloud ECS instance running **Ubuntu 22.04** in a mainland China region (e.g. cn-hangzhou, cn-shanghai)
- SSH access to the VPS as root or via sudo
- [v2rayN](https://github.com/2dust/v2rayN/releases) installed on Windows (download the `v2rayN-windows-64.zip` release)

---

## 1. VPS Setup

SSH into your Alibaba VPS and run:

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

```bash
curl --proxy socks5://127.0.0.1:10808 https://api.ip.sb/ip
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

## Future Clients

The same VPS and inbound works for all platforms — no server changes needed.

| Platform | Client |
|---|---|
| Linux | [NekoRay](https://github.com/MatsuriDayo/nekoray) or [Hiddify](https://github.com/hiddify/hiddify-app) |
| iOS | [Shadowrocket](https://apps.apple.com/app/shadowrocket/id932747118) or [Streisand](https://apps.apple.com/app/streisand/id6450534064) |

Both support VLESS share links exported from 3x-ui.
