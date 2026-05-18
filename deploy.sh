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

    # Generate secure UUID dynamically
    if command -v uuidgen >/dev/null 2>&1; then
        SECURE_UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
    elif [ -f /proc/sys/kernel/random/uuid ]; then
        SECURE_UUID=$(cat /proc/sys/kernel/random/uuid)
    else
        SECURE_UUID="cc654e3d-71b5-4a6c-b3a2-a3962b8a07c1"
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
    
    echo -e "\n${YELLOW}--- Part 2: cPanel FTP Configurations ---${NC}"
    BRIDGE_DOMAIN=$(prompt_input "Enter your cPanel Domain (e.g. yourdomain.com)")
    FTP_HOST=$(prompt_input "Enter cPanel FTP Host" "ftp.$BRIDGE_DOMAIN")
    FTP_USER=$(prompt_input "Enter FTP Username")
    FTP_PASS=$(prompt_input "Enter FTP Password" "" "true")

    APP_ROOT=$(prompt_input "Enter Application Root Directory on cPanel" "irantun-bridge")
    APP_URI=$(prompt_input "Enter Application URI / Path" "/")

    # 1. Connect to VPS and install Xray locally
    echo -e "\n${BLUE}--- Part 3: Deploying Exit Node locally on this VPS ---${NC}"
    echo "Installing Xray-core..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    
    echo "Configuring VLESS inbound on port 8080..."
    mkdir -p /usr/local/etc/xray
    cat <<XRAY_CONF > /usr/local/etc/xray/config.json
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": 8080,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$SECURE_UUID",
            "level": 0,
            "email": "love@$BRIDGE_DOMAIN"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/metrics" }
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

    # 2. Write local config.json locally for deployment
    echo -e "\n${BLUE}Generating bridge config file...${NC}"
    cat <<EOF > host/config.json
{
  "vpsIp": "$VPS_IP",
  "vpsPort": 8080,
  "vpsPath": "/metrics",
  "tunnelPath": "/api/v1/analytics",
  "secretUuid": "$SECURE_UUID",
  "port": 3000
}
EOF
    echo -e "${GREEN}✓ host/config.json updated successfully.${NC}"

    # 3. cPanel FTP deployment
    echo -e "\n${BLUE}--- Part 4: Connecting to cPanel via FTP ---${NC}"
    echo -e "${YELLOW}Uploading files to ftp://$FTP_HOST/$APP_ROOT...${NC}"

    # Upload all files in a single curl execution to avoid multiple connection overheads
    curl -u "$FTP_USER:$FTP_PASS" --ftp-create-dirs \
        -T host/app.js "ftp://$FTP_HOST/$APP_ROOT/app.js" \
        -T host/package.json "ftp://$FTP_HOST/$APP_ROOT/package.json" \
        -T host/config.json "ftp://$FTP_HOST/$APP_ROOT/config.json" \
        -T host/public/index.html "ftp://$FTP_HOST/$APP_ROOT/public/index.html" \
        -T host/public/style.css "ftp://$FTP_HOST/$APP_ROOT/public/style.css"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ All files uploaded successfully via FTP!${NC}"
    else
        echo -e "${RED}✗ FTP upload failed! Make sure your FTP credentials and host path are correct.${NC}"
        exit 1
    fi

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
    echo -e "vless://$SECURE_UUID@$BRIDGE_DOMAIN:443?type=ws&security=tls&path=%2Fapi%2Fv1%2Fanalytics&host=$BRIDGE_DOMAIN#IranTUN_HighSpeed_VLESS"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo -e "${GREEN}⚡ UNSECURED VLESS LINK (Port 80 HTTP):${NC}"
    echo -e "vless://$SECURE_UUID@$BRIDGE_DOMAIN:80?type=ws&security=none&path=%2Fapi%2Fv1%2Fanalytics&host=$BRIDGE_DOMAIN#IranTUN_Unsecured_VLESS"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo -e "${GREEN}⚡ SECRET DIAGNOSTICS & LIVE MONITORING CONSOLE:${NC}"
    echo -e "https://$BRIDGE_DOMAIN?secret=$SECURE_UUID"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
}

main
