#!/bin/bash

# IranTUN - One-Click Bash Deployer (Always run directly on your Foreign VPS)
# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_banner() {
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE}      IranTUN - Interactive Bash cPanel Deployer            ${NC}"
    echo -e "${BLUE}============================================================${NC}"
}

prompt_input() {
    local prompt_msg="$1"
    local default_val="$2"
    local is_secret="$3"
    local user_val=""

    if [ -n "$default_val" ]; then
        read -p "$prompt_msg [$default_val]: " user_val
        if [ -z "$user_val" ]; then
            echo "$default_val"
        else
            echo "$user_val"
        fi
    else
        while [ -z "$user_val" ]; do
            if [ "$is_secret" = "true" ]; then
                read -sp "$prompt_msg: " user_val
                echo "" >&2
            else
                read -p "$prompt_msg: " user_val
            fi
        done
        echo "$user_val"
    fi
}

main() {
    print_banner

    # Ensure running as root on VPS
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: Please run this script as root (sudo bash deploy.sh) directly on your VPS!${NC}"
        exit 1
    fi

    # Generate secure UUID dynamically for Web Panel (Admin Secret)
    if command -v uuidgen >/dev/null 2>&1; then
        ADMIN_SECRET=$(uuidgen | tr '[:upper:]' '[:lower:]')
    elif [ -f /proc/sys/kernel/random/uuid ]; then
        ADMIN_SECRET=$(cat /proc/sys/kernel/random/uuid)
    else
        ADMIN_SECRET="admin-secret-cc654e3d-71b5"
    fi

    # Generate distinct UUID for the first VLESS user
    if command -v uuidgen >/dev/null 2>&1; then
        USER_UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
    elif [ -f /proc/sys/kernel/random/uuid ]; then
        USER_UUID=$(cat /proc/sys/kernel/random/uuid)
    else
        USER_UUID="user-uuid-a3962b8a07c1"
    fi

    echo -e "\n${YELLOW}--- Part 1: Foreign VPS Setup ---${NC}"
    echo -e "${BLUE}Detecting public IP of this VPS...${NC}"
    VPS_IP=$(curl -s https://api.ipify.org)
    if [ -z "$VPS_IP" ]; then
        VPS_IP=$(curl -s http://ifconfig.me)
    fi
    
    if [ -n "$VPS_IP" ]; then
        echo -e "${GREEN}✓ Detected VPS IP: $VPS_IP${NC}"
    else
        VPS_IP=$(prompt_input "Failed to auto-detect IP. Enter Foreign VPS IP Address")
    fi
    
    echo -e "\nChoose connection protocol between Bridge (cPanel) and this VPS:"
    echo "1) Plain WebSocket (ws) - Unencrypted, vulnerable to DPI throttling"
    echo "2) Secure WebSocket (wss) - Encrypted using TLS with self-signed certificate (recommended)"
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

    echo -e "\n${YELLOW}--- Advanced Host Settings ---${NC}"
    echo "Do you want to enable Adaptive Upload (Batching) to increase upload speed and save cPanel CPU?"
    echo "Note: This adds a slight ping delay (e.g., 10-15ms) to game traffic."
    ADAPTIVE_CHOICE=$(prompt_input "Enable Adaptive Upload? (y/n)" "n")
    if [[ "$ADAPTIVE_CHOICE" =~ ^[Yy]$ ]]; then
        ADAPTIVE_ENABLE="true"
        ADAPTIVE_DELAY=$(prompt_input "Enter batching delay in milliseconds (e.g. 15)" "15")
    else
        ADAPTIVE_ENABLE="false"
        ADAPTIVE_DELAY="15"
    fi

    echo -e "\nDo you want to install Cloudflare WARP (SOCKS5 Proxy) to hide the VPS IP and bypass geo-blocks?"
    echo "Note: This routes outgoing traffic through WARP."
    WARP_CHOICE=$(prompt_input "Install WARP? (y/n)" "y")
    if [[ "$WARP_CHOICE" =~ ^[Yy]$ ]]; then
        WARP_ENABLE="true"
    else
        WARP_ENABLE="false"
    fi

    echo -e "\n${YELLOW}--- Part 2: cPanel FTP Configurations ---${NC}"
    BRIDGE_DOMAIN=$(prompt_input "Enter your cPanel Domain (e.g. yourdomain.com)")
    FTP_HOST=$(prompt_input "Enter cPanel FTP Host" "ftp.$BRIDGE_DOMAIN")
    FTP_USER=$(prompt_input "Enter FTP Username")
    FTP_PASS=$(prompt_input "Enter FTP Password" "" "true")

    APP_ROOT=$(prompt_input "Enter Application Root Directory on cPanel" "irantun-bridge")
    APP_URI=$(prompt_input "Enter Application URI / Path" "/")

    # 1. Connect to VPS and install Xray locally
    echo -e "\n${BLUE}--- Part 3: Deploying Exit Node locally on this VPS ---${NC}"
    echo "Installing required packages (jq, curl)..."
    if [ -f /etc/debian_version ]; then
        apt-get update -y && apt-get install -y jq curl
    elif [ -f /etc/redhat-release ]; then
        yum install -y jq curl
    fi

    echo "Installing Xray-core..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    
    if [ "$VPS_PROTOCOL" = "wss" ]; then
        echo "Generating self-signed SSL certificate for VPS..."
        openssl req -newkey rsa:2048 -nodes -keyout /usr/local/etc/xray/vps.key -x509 -days 365 -out /usr/local/etc/xray/vps.crt -subj "/CN=$BRIDGE_DOMAIN"
        chmod 755 /usr/local/etc/xray
        chmod 644 /usr/local/etc/xray/vps.key /usr/local/etc/xray/vps.crt
    fi

    echo "Configuring VLESS inbound on port $VPS_PORT..."
    mkdir -p /usr/local/etc/xray
    cat <<XRAY_CONF > /usr/local/etc/xray/config.json
{
  "log": { "loglevel": "warning" },
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
        "wsSettings": { "path": "/metrics" }$TLS_CONFIG_BLOCK
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "settings": {}, "tag": "direct" },
    { "protocol": "blackhole", "settings": {}, "tag": "blocked" }
  ],
  "routing": {
    "rules": [
      { "type": "field", "ip": ["geoip:private"], "outboundTag": "blocked" }
    ]
  }
}
XRAY_CONF

    if [ "$WARP_ENABLE" = "true" ]; then
      sed -i 's/"outbounds": \[/"outbounds": \[ { "protocol": "socks", "settings": { "servers": [ { "address": "127.0.0.1", "port": 40000 } ] }, "tag": "warp" },/g' /usr/local/etc/xray/config.json
    fi

    echo "Restarting Xray daemon..."
    systemctl daemon-reload
    systemctl restart xray
    systemctl enable xray
    
    sleep 1
    if systemctl is-active --quiet xray; then
        echo -e "${GREEN}✓ Xray Exit Node is active locally and running beautifully!${NC}"
    else
        echo -e "${RED}⚠ Warning: Xray service failed to start or state is unknown.${NC}"
    fi

    if [ "$WARP_ENABLE" = "true" ]; then
        echo -e "\n${BLUE}Installing WireProxy (Cloudflare WARP via SOCKS5 on 40000)...${NC}"
        
        # Download wgcf and wireproxy
        curl -fsSL -o /usr/local/bin/wgcf https://github.com/ViRb3/wgcf/releases/download/v2.2.22/wgcf_2.2.22_linux_amd64
        chmod +x /usr/local/bin/wgcf
        
        curl -fsSL -o /tmp/wireproxy.tar.gz https://github.com/pufferffish/wireproxy/releases/download/v1.0.7/wireproxy_linux_amd64.tar.gz
        tar -xzf /tmp/wireproxy.tar.gz -C /tmp
        mv /tmp/wireproxy /usr/local/bin/
        chmod +x /usr/local/bin/wireproxy
        rm -f /tmp/wireproxy.tar.gz
        
        mkdir -p /usr/local/etc/wireproxy
        cd /usr/local/etc/wireproxy
        
        # Generate WARP config
        echo -e "Registering free WARP account (this may take a moment)..."
        yes | /usr/local/bin/wgcf register --accept-tos >/dev/null 2>&1
        /usr/local/bin/wgcf generate >/dev/null 2>&1
        
        if [ -f wgcf-profile.conf ]; then
            PRIV_KEY=$(grep '^PrivateKey' wgcf-profile.conf | cut -d '=' -f 2 | tr -d ' ')
            PUB_KEY=$(grep '^PublicKey' wgcf-profile.conf | cut -d '=' -f 2 | tr -d ' ')
            ENDPOINT=$(grep '^Endpoint' wgcf-profile.conf | cut -d '=' -f 2 | tr -d ' ')
            ADDRESS=$(grep '^Address' wgcf-profile.conf | head -n 1 | cut -d '=' -f 2 | tr -d ' ')
            
            cat <<EOF > wireproxy.conf
[Interface]
Address = $ADDRESS
PrivateKey = $PRIV_KEY
MTU = 1280
DNS = 1.1.1.1

[Peer]
PublicKey = $PUB_KEY
Endpoint = $ENDPOINT

[Socks5]
BindAddress = 127.0.0.1:40000
EOF
            
            cat <<EOF > /etc/systemd/system/wireproxy.service
[Unit]
Description=WireProxy for WARP
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/wireproxy -c /usr/local/etc/wireproxy/wireproxy.conf
Restart=always
RestartSec=5
User=root
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
            
            systemctl daemon-reload
            systemctl enable wireproxy
            systemctl start wireproxy
            
            sleep 2
            if systemctl is-active --quiet wireproxy; then
                echo -e "${GREEN}✓ WireProxy running successfully on 127.0.0.1:40000${NC}"
            else
                echo -e "${RED}⚠ WireProxy failed to start.${NC}"
            fi
        else
            echo -e "${RED}⚠ Failed to generate WARP profile (Cloudflare API block?). SOCKS5 won't work.${NC}"
        fi
        cd - >/dev/null
    fi

    echo -e "\n${BLUE}Installing CLI Management Menu...${NC}"
    GITHUB_RAW="https://raw.githubusercontent.com/ramin-mahmoodi/IranTUN/main"
    curl -s -L "$GITHUB_RAW/vps/irantun-menu.sh" -o /usr/local/bin/irantun
    chmod +x /usr/local/bin/irantun
    echo -e "${GREEN}✓ CLI Menu installed. You can type 'irantun' anytime to manage your VPS.${NC}"

    # 2. Setup temporary workspace and download bridge files
    echo -e "\n${BLUE}Preparing temporary workspace...${NC}"
    TEMP_DIR=$(mktemp -d -t irantun-XXXXXXXXXX)
    mkdir -p "$TEMP_DIR/host/public"
    
    GITHUB_RAW="https://raw.githubusercontent.com/ramin-mahmoodi/IranTUN/main"
    echo "Downloading latest bridge files from GitHub..."
    curl -s -L "$GITHUB_RAW/host/app.js" -o "$TEMP_DIR/host/app.js"
    curl -s -L "$GITHUB_RAW/host/package.json" -o "$TEMP_DIR/host/package.json"
    curl -s -L "$GITHUB_RAW/host/public/index.html" -o "$TEMP_DIR/host/public/index.html"
    curl -s -L "$GITHUB_RAW/host/public/style.css" -o "$TEMP_DIR/host/public/style.css"

    echo -e "${BLUE}Generating bridge config file...${NC}"
    cat <<EOF > "$TEMP_DIR/host/config.json"
{
  "vpsIp": "$VPS_IP",
  "vpsPort": $VPS_PORT,
  "vpsProtocol": "$VPS_PROTOCOL",
  "vpsPath": "/metrics",
  "tunnelPath": "/api/v1/analytics",
  "secretUuid": "$ADMIN_SECRET",
  "port": 3000,
  "adaptiveUpload": $ADAPTIVE_ENABLE,
  "adaptiveDelayMs": $ADAPTIVE_DELAY
}
EOF
    echo -e "${GREEN}✓ config.json generated successfully.${NC}"

    # 3. cPanel FTP deployment
    echo -e "\n${BLUE}--- Part 4: Connecting to cPanel via FTP ---${NC}"
    echo -e "${YELLOW}Uploading files to ftp://$FTP_HOST/$APP_ROOT...${NC}"

    # Upload all files in a single curl execution to avoid multiple connection overheads
    curl -u "$FTP_USER:$FTP_PASS" --ftp-create-dirs \
        -T "$TEMP_DIR/host/app.js" "ftp://$FTP_HOST/$APP_ROOT/app.js" \
        -T "$TEMP_DIR/host/package.json" "ftp://$FTP_HOST/$APP_ROOT/package.json" \
        -T "$TEMP_DIR/host/config.json" "ftp://$FTP_HOST/$APP_ROOT/config.json" \
        -T "$TEMP_DIR/host/public/index.html" "ftp://$FTP_HOST/$APP_ROOT/public/index.html" \
        -T "$TEMP_DIR/host/public/style.css" "ftp://$FTP_HOST/$APP_ROOT/public/style.css"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ All files uploaded successfully via FTP!${NC}"
    else
        echo -e "${RED}✗ FTP upload failed! Make sure your FTP credentials and host path are correct.${NC}"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    # Clean up temporary workspace
    rm -rf "$TEMP_DIR"

    # Output Client links
    echo -e "\n${GREEN}============================================================${NC}"
    echo -e "${GREEN}🎉 IRANTUN TUNNEL INTEGRATION COMPLETED SUCCESSFULLY! 🎉${NC}"
    echo -e "${GREEN}============================================================${NC}"

    echo -e "\n${YELLOW}📝 MANUAL CPANEL SETUP INSTRUCTIONS:${NC}"
    echo "Since shared hosts do not have SSH, please finalize the Node.js application registration in cPanel UI:"
    echo "1) Open 'Setup Node.js App' in your cPanel dashboard."
    echo "2) Click 'Create Application'."
    echo "3) Enter the following values:"
    echo "   - Application root: $APP_ROOT"
    echo "   - Application URL: Select $BRIDGE_DOMAIN and set path to '$APP_URI'"
    echo "   - Application startup file: app.js"
    echo "4) Click 'CREATE' on the top-right corner."
    echo "5) Click the 'Run NPM Install' button to fetch dependencies."

    echo -e "\nReady-to-use Client Configurations:"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo -e "${GREEN}⚡ SECURED VLESS LINK (Port 443 with SSL):${NC}"
    echo -e "vless://$USER_UUID@$BRIDGE_DOMAIN:443?type=ws&security=tls&path=%2Fapi%2Fv1%2Fanalytics&host=$BRIDGE_DOMAIN#IranTUN_HighSpeed_VLESS"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo -e "${GREEN}⚡ UNSECURED VLESS LINK (Port 80 HTTP):${NC}"
    echo -e "vless://$USER_UUID@$BRIDGE_DOMAIN:80?type=ws&security=none&path=%2Fapi%2Fv1%2Fanalytics&host=$BRIDGE_DOMAIN#IranTUN_Unsecured_VLESS"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo -e "${GREEN}🔒 SECRET DIAGNOSTICS & LIVE MONITORING CONSOLE:${NC}"
    echo -e "https://$BRIDGE_DOMAIN?secret=$ADMIN_SECRET"
    echo -e "${BLUE}------------------------------------------------------------${NC}"

    echo -e "\n${BLUE}*** IMPORTANT: Web Panel Configuration ***${NC}"
    if [ "$ADAPTIVE_ENABLE" = "true" ]; then
      echo -e "1. Go to your Admin Panel and set 'Adaptive Upload' to: ${GREEN}On (Low CPU, High Speed)${NC}"
      echo -e "2. Set 'Batching Delay' to: ${GREEN}${ADAPTIVE_DELAY}ms${NC}"
    else
      echo -e "1. Go to your Admin Panel and set 'Adaptive Upload' to: ${GREEN}Off (Zero Ping, High CPU)${NC}"
    fi
    echo -e "3. Click 'Save & Apply Settings'"
    echo -e "${BLUE}============================================================${NC}"
}

main
