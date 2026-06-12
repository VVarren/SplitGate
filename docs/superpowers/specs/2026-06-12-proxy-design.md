# Proxy Design — VLESS + Xray-core via 3x-ui

**Date:** 2026-06-12  
**Status:** Approved

## Purpose

Route traffic through an Alibaba Cloud VPS located in mainland China so that Chinese region-locked anime (dubs and subs) can be accessed. The VPS IP appears as the origin to streaming sites.

## Architecture

```
User Machine (Windows)
  └─ v2rayN (GUI client)
       └─ VLESS over TCP + TLS ──► Alibaba Cloud VPS (mainland China)
                                        └─ 3x-ui web panel
                                             └─ Xray-core
                                                  └─► Chinese streaming sites
```

Split tunneling is used: only Chinese streaming traffic routes through the VPS. All other traffic goes direct, preserving normal internet speeds.

## Components

```
proxy/
├── server/
│   └── install.sh          # Installs 3x-ui on the VPS, opens firewall port
├── client/
│   └── routing.json        # v2rayN routing rules for split tunneling
└── README.md               # End-to-end setup guide
```

### server/install.sh
- Runs on the Alibaba VPS (Ubuntu/Debian)
- Installs 3x-ui via its official installer
- Opens the 3x-ui web panel port in the firewall (ufw)
- Prints the panel URL on completion
- Post-install: user creates the VLESS inbound through the 3x-ui web UI and copies the share link

### client/routing.json
- Imported into v2rayN on Windows
- Routes Chinese streaming domains (Bilibili, iQIYI, Youku, etc.) through the VLESS proxy
- All other domains go direct (split tunnel)
- Uses `geosite:cn` and explicit domain rules for major streaming platforms

### README.md
Covers:
1. VPS prerequisites (Alibaba Cloud ECS, Ubuntu 22.04 recommended)
2. Running `install.sh` via SSH
3. 3x-ui post-install configuration (create VLESS inbound, copy share link)
4. Importing the share link and `routing.json` into v2rayN on Windows
5. Verification step

## Data Flow

1. Browser request hits a Chinese streaming domain
2. v2rayN matches the domain against routing rules
3. Match → traffic tunneled over VLESS to VPS; streaming site sees Chinese IP
4. No match → traffic goes direct; user's real IP is used

## Error Handling

- VPS unreachable: v2rayN falls back to direct; geo-locked content fails but regular internet continues
- 3x-ui provides a live traffic monitor for connection diagnostics
- VLESS connection is TLS-encrypted end-to-end

## Testing

```bash
# Verify the proxy returns a Chinese IP
curl --proxy socks5://127.0.0.1:10808 https://api.ip.sb/ip
```

Then confirm a Chinese streaming site loads and content is accessible.

## Future Expansion

- **Linux**: NekoRay or Hiddify — both support VLESS and import share links
- **iOS**: Streisand or Shadowrocket — both support VLESS share links from 3x-ui
- The same VPS and 3x-ui inbound works for all clients with no server changes
