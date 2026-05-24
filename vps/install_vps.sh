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

read -p "Enter secure UUID for Web Panel Admin Secret (press Enter to auto-generate): " ADMIN_SECRET
if [ -z "$ADMIN_SECRET" ]; then
  if command -v uuidgen &> /dev/null; then
    ADMIN_SECRET=$(uuidgen)
  elif [ -f /proc/sys/kernel/random/uuid ]; then
    ADMIN_SECRET=$(cat /proc/sys/kernel/random/uuid)
  else
    ADMIN_SECRET="admin-secret-cc654e3d-71b5" # Fallback
  fi
fi

# Automatically generate a distinct UUID for the first VLESS user
if command -v uuidgen &> /dev/null; then
  USER_UUID=$(uuidgen)
elif [ -f /proc/sys/kernel/random/uuid ]; then
  USER_UUID=$(cat /proc/sys/kernel/random/uuid)
else
  USER_UUID="user-uuid-a3962b8a07c1" # Fallback
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

echo -e "\n${BLUE}--- Advanced Host Settings ---${NC}"
echo "Do you want to enable Adaptive Upload (Batching) to increase upload speed and save cPanel CPU?"
echo "Note: This adds a slight ping delay (e.g., 10-15ms) to game traffic."
read -p "Enable Adaptive Upload? (y/n) [n]: " ADAPTIVE_CHOICE
if [[ "$ADAPTIVE_CHOICE" =~ ^[Yy]$ ]]; then
  ADAPTIVE_ENABLE="true"
  read -p "Enter batching delay in milliseconds (e.g. 15): [15] " ADAPTIVE_DELAY
  if [ -z "$ADAPTIVE_DELAY" ]; then
    ADAPTIVE_DELAY="15"
  fi
else
  ADAPTIVE_ENABLE="false"
  ADAPTIVE_DELAY="15"
fi

echo -e "\nDo you want to install Cloudflare WARP (SOCKS5 Proxy) to hide the VPS IP and bypass geo-blocks?"
echo "Note: This routes outgoing traffic through WARP."
read -p "Install WARP? (y/n) [y]: " WARP_CHOICE
if [[ "$WARP_CHOICE" =~ ^[Yy]$ ]] || [ -z "$WARP_CHOICE" ]; then
  WARP_ENABLE="true"
else
  WARP_ENABLE="false"
fi

echo -e "\n${BLUE}Using Web Admin Secret: ${GREEN}$ADMIN_SECRET${NC}"
echo -e "${BLUE}Using VLESS User UUID: ${GREEN}$USER_UUID${NC}"
echo -e "${BLUE}Using Domain: ${GREEN}$BRIDGE_DOMAIN${NC}"
echo -e "${BLUE}Using Protocol: ${GREEN}$VPS_PROTOCOL${NC} on port ${GREEN}$VPS_PORT${NC}"
echo -e "${BLUE}Adaptive Upload Recommended Settings: ${GREEN}Enabled: $ADAPTIVE_ENABLE, Delay: ${ADAPTIVE_DELAY}ms${NC}"

echo -e "${BLUE}[1/4] Installing required packages and Xray-core...${NC}"
if [ -f /etc/debian_version ]; then
    apt-get update -y && apt-get install -y jq curl
elif [ -f /etc/redhat-release ]; then
    yum install -y jq curl
fi
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
  openssl req -newkey rsa:2048 -nodes -keyout /usr/local/etc/xray/vps.key -x509 -days 365 -out /usr/local/etc/xray/vps.crt -subj "/CN=$BRIDGE_DOMAIN"
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
            "email": "Admin_User@$BRIDGE_DOMAIN"
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

if [ "$WARP_ENABLE" = "true" ]; then
  sed -i 's/"outbounds": \[/"outbounds": \[ { "protocol": "socks", "settings": { "servers": [ { "address": "127.0.0.1", "port": 40000 } ] }, "tag": "warp" },/g' "$CONFIG_DIR/config.json"
fi

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

if [ "$WARP_ENABLE" = "true" ]; then
  echo -e "\n${BLUE}[4.5/6] Installing Cloudflare WARP (SOCKS5 Proxy on 40000)...${NC}"
  if [ -f /etc/debian_version ]; then
      apt-get update -y && apt-get install -y gnupg lsb-release curl
      curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
      echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list
      apt-get update -y && apt-get install -y cloudflare-warp
      warp-cli --accept-tos registration new
      warp-cli --accept-tos mode proxy
      warp-cli --accept-tos proxy port 40000
      warp-cli --accept-tos connect
      sleep 2
      echo -e "${GREEN}✓ WARP proxy running on 127.0.0.1:40000${NC}"
  else
      echo -e "${RED}✗ WARP automatic installation is only supported on Debian/Ubuntu.${NC}"
  fi
fi

echo -e "\n${BLUE}[5/6] Installing CLI Management Menu...${NC}"
GITHUB_RAW="https://raw.githubusercontent.com/ramin-mahmoodi/IranTUN/main"
curl -s -L "$GITHUB_RAW/vps/irantun-menu.sh" -o /usr/local/bin/irantun
chmod +x /usr/local/bin/irantun
echo -e "${GREEN}✓ CLI Menu installed. You can type 'irantun' anytime to manage your VPS.${NC}"

echo -e "\n${BLUE}[6/6] Generating ready-to-use Client Configurations...${NC}"
echo -e "${BLUE}=========================================================================${NC}"
echo -e "${GREEN}IranTUN VPS is fully active!${NC}"
echo -e ""
echo -e "You can now deploy the 'host' folder to your Iran Node.js Host."
echo -e "IMPORTANT: When configuring host/config.json, use the ADMIN_SECRET for secretUuid."
echo -e ""
echo -e "Once the host is active, add this VLESS connection in V2rayNG, Nekobox, or Shadowrocket:"
echo -e ""
echo -e "${BLUE}-------------------------------------------------------------------------${NC}"
echo -e "${GREEN}VLESS URI (Import directly into Nekobox / V2rayNG):${NC}"
echo -e "vless://$USER_UUID@$BRIDGE_DOMAIN:443?type=ws&security=tls&path=%2Fapi%2Fv1%2Fanalytics&host=$BRIDGE_DOMAIN#IranTUN_HighSpeed_VLESS"
echo -e "${BLUE}-------------------------------------------------------------------------${NC}"
echo -e ""
echo -e "${BLUE}*** IMPORTANT: Web Panel Configuration ***${NC}"
echo -e "Because IranTUN is a Forward-Bridge, the Adaptive Upload settings must be configured on your cPanel Host."
echo -e "Go to your secret Admin Panel: https://$BRIDGE_DOMAIN/?secret=$ADMIN_SECRET"
if [ "$ADAPTIVE_ENABLE" = "true" ]; then
  echo -e "1. Set 'Adaptive Upload (Batching)' to: ${GREEN}On (Low CPU, High Speed)${NC}"
  echo -e "2. Set 'Batching Delay' to: ${GREEN}${ADAPTIVE_DELAY}ms${NC}"
else
  echo -e "1. Set 'Adaptive Upload (Batching)' to: ${GREEN}Off (Zero Ping, High CPU)${NC}"
fi
echo -e "3. Click 'Save & Apply Settings'"
echo -e "${BLUE}=========================================================================${NC}"
