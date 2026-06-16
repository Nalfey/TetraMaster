#!/usr/bin/env bash
# One-time Cloudflare Tunnel setup on the Oracle relay VM.
set -euo pipefail

TUNNEL_NAME="${TM_TUNNEL_NAME:-tetramaster-relay}"
HOSTNAME="${TM_RELAY_HOSTNAME:-relay.tetramasters.uk}"
CONFIG_DIR="/opt/tetramaster/config"
BIN_DIR="/opt/tetramaster/bin"

echo "=== TetraMaster Cloudflare Tunnel setup ==="
echo "Tunnel name: $TUNNEL_NAME"
echo "Hostname:    $HOSTNAME"
echo ""

if ! command -v cloudflared >/dev/null 2>&1; then
  echo "cloudflared not installed. Run build/vm-prep.sh first."
  exit 1
fi

if [ ! -f "$HOME/.cloudflared/cert.pem" ]; then
  echo "Cloudflare login required (one time)."
  echo "Run:  cloudflared tunnel login"
  echo "Open the URL in a browser and authorize tetramasters.uk."
  exit 2
fi

sudo mkdir -p "$CONFIG_DIR"
sudo chown -R ubuntu:ubuntu /opt/tetramaster

if [ ! -d /opt/tetramaster/venv ]; then
  echo "=== Python venv for ws_bridge ==="
  python3 -m venv /opt/tetramaster/venv
  /opt/tetramaster/venv/bin/pip install --upgrade pip
  /opt/tetramaster/venv/bin/pip install -r "$BIN_DIR/requirements.txt"
fi

TUNNEL_ID=""
if cloudflared tunnel list 2>/dev/null | grep -q "$TUNNEL_NAME"; then
  TUNNEL_ID=$(cloudflared tunnel list | awk -v name="$TUNNEL_NAME" '$2 == name { print $1; exit }')
  echo "Using existing tunnel $TUNNEL_NAME ($TUNNEL_ID)"
else
  echo "=== Creating tunnel $TUNNEL_NAME ==="
  cloudflared tunnel create "$TUNNEL_NAME"
  TUNNEL_ID=$(cloudflared tunnel list | awk -v name="$TUNNEL_NAME" '$2 == name { print $1; exit }')
fi

if [ -z "$TUNNEL_ID" ]; then
  echo "Could not resolve tunnel ID for $TUNNEL_NAME"
  exit 1
fi

CREDS="$CONFIG_DIR/tunnel-credentials.json"
if [ ! -f "$CREDS" ]; then
  if [ -f "$HOME/.cloudflared/${TUNNEL_ID}.json" ]; then
    cp "$HOME/.cloudflared/${TUNNEL_ID}.json" "$CREDS"
  else
    echo "Missing credentials JSON for tunnel $TUNNEL_ID"
    exit 1
  fi
fi

cat > "$CONFIG_DIR/config.yml" <<EOF
tunnel: ${TUNNEL_ID}
credentials-file: ${CREDS}

ingress:
  - hostname: ${HOSTNAME}
    service: http://127.0.0.1:8080
  - service: http_status:404
EOF

echo "=== DNS route (CNAME) ==="
cloudflared tunnel route dns "$TUNNEL_NAME" "$HOSTNAME" || true
echo ""
echo "If relay.tetramasters.uk still has a grey-cloud A record, delete it in Cloudflare DNS."
echo "The tunnel route creates a proxied CNAME automatically."
echo ""

echo "=== systemd services ==="
sudo cp /tmp/tetramaster-ws-bridge.service /etc/systemd/system/tetramaster-ws-bridge.service
sudo cp /tmp/tetramaster-cloudflared.service /etc/systemd/system/tetramaster-cloudflared.service
sudo cp /tmp/tetramaster-relay.service /etc/systemd/system/tetramaster-relay.service
sudo systemctl daemon-reload
sudo systemctl enable tetramaster-relay tetramaster-ws-bridge tetramaster-cloudflared
sudo systemctl restart tetramaster-relay tetramaster-ws-bridge tetramaster-cloudflared
sleep 2
sudo systemctl --no-pager status tetramaster-relay tetramaster-ws-bridge tetramaster-cloudflared

echo ""
echo "=== Done ==="
echo "Relay TCP: 127.0.0.1:19876 (localhost only)"
echo "WebSocket: 127.0.0.1:8080 -> Cloudflare -> wss://${HOSTNAME}/"
echo "Close Oracle Cloud security list port 19876 when verified."
