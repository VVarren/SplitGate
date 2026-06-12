#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root: sudo bash install.sh"
  exit 1
fi

echo "[1/3] Installing prerequisites..."
apt-get update -y
apt-get install -y curl wget ufw

echo "[2/3] Installing 3x-ui..."
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

echo "[3/3] Configuring firewall..."
ufw allow 2053/tcp   # 3x-ui web panel
ufw allow 443/tcp    # VLESS inbound
ufw --force enable

SERVER_IP=$(curl -s https://api.ip.sb/ip)

echo ""
echo "=============================="
echo "3x-ui installed successfully!"
echo ""
echo "Panel URL : http://$SERVER_IP:2053/xui"
echo "Username  : admin"
echo "Password  : admin"
echo ""
echo "IMPORTANT: Change the default password immediately after logging in."
echo "=============================="
