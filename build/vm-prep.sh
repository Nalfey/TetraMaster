#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "=== System update ==="
sudo apt-get update -qq
sudo apt-get upgrade -y -qq

echo "=== Base packages ==="
sudo apt-get install -y -qq \
  ca-certificates curl git jq unzip ufw \
  lua5.4 luarocks python3-venv python3-pip \
  build-essential libssl-dev

echo "=== cloudflared ==="
if ! command -v cloudflared >/dev/null 2>&1; then
  tmp=$(mktemp)
  curl -fsSL -o "$tmp" https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
  sudo install -m 755 "$tmp" /usr/local/bin/cloudflared
  rm -f "$tmp"
fi
cloudflared --version

echo "=== Firewall (ufw + Oracle iptables) ==="
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw --force enable
sudo ufw status verbose

# Remove legacy public relay port if present from older installs.
if [ -f /etc/iptables/rules.v4 ] && grep -q 'dport 19876' /etc/iptables/rules.v4; then
  sudo sed -i '/dport 19876/d' /etc/iptables/rules.v4
  sudo iptables-restore < /etc/iptables/rules.v4
fi

echo "=== Relay prep directories ==="
sudo mkdir -p /opt/tetramaster/bin /opt/tetramaster/log /opt/tetramaster/config
sudo chown -R ubuntu:ubuntu /opt/tetramaster

echo "=== Versions ==="
lua5.4 -v
luarocks --version
uname -a
free -h
df -h /

echo "=== VM prep complete ==="
