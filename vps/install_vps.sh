#!/bin/bash

# IranTUN - One-Click Foreign VPS Setup Script
# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}    IranTUN - One-Click VPS Installer          ${NC}"
echo -e "${BLUE}===============================================${NC}"

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Please run this script as root (sudo bash install_vps.sh)${NC}"
  exit 1
fi

# Generate or ask for configuration parameters
read -p "Enter secure UUID (press Enter to auto-generate): " USER_UUID
if [ -z "$USER_UUID" ]; then
  if command -v uuidgen &> /dev/null; then
    USER_UUID=$(uuidgen)
  elif [ -f /proc/sys/kernel/random/uuid ]; then
    USER_UUID=$(cat /proc/sys/kernel/random/uuid)
  else
    USER_UUID="cc654e3d-71b5-4a6c-b3a2-a3962b8a07c1" # Fallback
  fi
fi

read -p "Enter cPanel Bridge Domain (e.g. yourdomain.com): " BRIDGE_DOMAIN
if [ -z "$BRIDGE_DOMAIN" ]; then
  BRIDGE_DOMAIN="yourdomain.com"
fi

echo -e "\nChoose connection protocol between Bridge (cPanel) and this VPS:"
echo "1) Plain WebSocket (ws) - Unencrypted, port 8080"
echo "2) Secure WebSocket (wss) - Encrypted using TLS with self-signed certificate, port 8443 (recommended)"
read -p "Select option [2]: " PROTO_OPTION
if [ "$PROTO_OPTION" = "1" ]; then
  VPS_PROTOCOL="ws"
  VPS_PORT=8080
  TLS_CONFIG_BLOCK=""
else
  VPS_PROTOCOL="wss"
  VPS_PORT=8443
  TLS_CONFIG_BLOCK=',
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/usr/local/etc/xray/vps.crt",
              "keyFile": "/usr/local/etc/xray/vps.key"
            }
          ]
        }'
fi

echo -e "${BLUE}Using UUID: ${GREEN}$USER_UUID${NC}"
echo -e "${BLUE}Using Domain: ${GREEN}$BRIDGE_DOMAIN${NC}"
echo -e "${BLUE}Using Protocol: ${GREEN}$VPS_PROTOCOL${NC} on port ${GREEN}$VPS_PORT${NC}"

echo -e "${BLUE}[1/4] Installing Xray-core officially...${NC}"
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ Xray-core installed successfully!${NC}"
else
  echo -e "${RED}✗ Failed to install Xray-core.${NC}"
  exit 1
fi

echo -e "${BLUE}[2/4] Injecting secure VLESS-WS configurations...${NC}"
CONFIG_DIR="/usr/local/etc/xray"
mkdir -p "$CONFIG_DIR"

if [ "$VPS_PROTOCOL" = "wss" ]; then
  echo "Generating self-signed SSL certificate for VPS..."
  openssl req -newkey rsa:2048 -nodes -keyout /usr/local/etc/xray/vps.key -x509 -days 365 -out /usr/local/etc/xray/vps.crt -subj "/C=US/ST=CA/L=Los Angeles/O=Speedtest Inc/CN=www.speedtest.net"
  chmod 755 /usr/local/etc/xray
  chmod 644 /usr/local/etc/xray/vps.key /usr/local/etc/xray/vps.crt
fi

cat << EOF > "$CONFIG_DIR/config.json"
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $VPS_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$USER_UUID",
            "level": 0,
            "email": "love@$BRIDGE_DOMAIN"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/metrics"
        }$TLS_CONFIG_BLOCK
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF

echo -e "${GREEN}✓ VLESS-WS config injected into $CONFIG_DIR/config.json${NC}"

echo -e "${BLUE}[3/4] Starting and enabling Xray systemd daemon...${NC}"
systemctl daemon-reload
systemctl restart xray
systemctl enable xray

sleep 2
if systemctl is-active --quiet xray; then
  echo -e "${GREEN}✓ Xray service is running beautifully in background!${NC}"
else
  echo -e "${RED}✗ Error: Xray service failed to start. Check logs via 'journalctl -u xray'${NC}"
  exit 1
fi

echo -e "${BLUE}[4/4] Generating ready-to-use Client Configurations...${NC}"
echo -e "${BLUE}=========================================================================${NC}"
echo -e "${GREEN}IranTUN VPS is fully active!${NC}"
echo -e ""
echo -e "You can now deploy the 'host' folder to your Iran Node.js Host."
echo -e "Once the host is active, add this VLESS connection in V2rayNG, Nekobox, or Shadowrocket:"
echo -e ""
echo -e "${BLUE}-------------------------------------------------------------------------${NC}"
echo -e "${GREEN}VLESS URI (Import directly into Nekobox / V2rayNG):${NC}"
echo -e "vless://$USER_UUID@$BRIDGE_DOMAIN:443?type=ws&security=tls&path=%2Fapi%2Fv1%2Fanalytics&host=$BRIDGE_DOMAIN#IranTUN_HighSpeed_VLESS"
echo -e "${BLUE}-------------------------------------------------------------------------${NC}"
echo -e ""
echo -e "Or if you haven't activated SSL on your host yet, use the HTTP non-TLS version (port 80):"
echo -e "vless://$USER_UUID@$BRIDGE_DOMAIN:80?type=ws&security=none&path=%2Fapi%2Fv1%2Fanalytics&host=$BRIDGE_DOMAIN#IranTUN_Unsecured_VLESS"
echo -e ""
echo -e "${BLUE}=========================================================================${NC}"
