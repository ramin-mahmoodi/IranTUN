#!/bin/bash

# IranTUN - One-Click Shell Deployer for Unix/macOS/Git-Bash
# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_banner() {
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE}      IranTUN - Interactive Bash Multi-Deployer             ${NC}"
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

    # Generate secure UUID dynamically
    if command -v uuidgen >/dev/null 2>&1; then
        SECURE_UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
    elif [ -f /proc/sys/kernel/random/uuid ]; then
        SECURE_UUID=$(cat /proc/sys/kernel/random/uuid)
    else
        # fallback
        SECURE_UUID="cc654e3d-71b5-4a6c-b3a2-a3962b8a07c1"
    fi

    echo -e "\n${YELLOW}--- Part 1: Foreign VPS Exit Node Configuration ---${NC}"
    VPS_IP=$(prompt_input "Enter Foreign VPS IP Address")
    VPS_PORT=$(prompt_input "Enter Foreign VPS SSH Port" "22")
    
    echo -e "\n${YELLOW}--- Part 2: cPanel Bridge Configurations ---${NC}"
    BRIDGE_DOMAIN=$(prompt_input "Enter your cPanel Domain (e.g. yourdomain.com)")
    
    echo -e "\nSelect Deployment Method for cPanel Host:"
    echo "1) Fully Automated (via SSH - Creates and configures Node.js app automatically)"
    echo "2) Semi-Automated (via FTP - Uploads files, manual cPanel setup)"
    METHOD=$(prompt_input "Enter choice (1 or 2)" "1")

    APP_ROOT=$(prompt_input "Enter Application Root Directory on cPanel" "irantun-bridge")
    APP_URI=$(prompt_input "Enter Application URI / Path" "/")

    if [ "$METHOD" = "1" ]; then
        echo -e "\n${YELLOW}--- Method 1 Selected: SSH Automated Deployment ---${NC}"
        CP_SSH_HOST=$(prompt_input "Enter cPanel Host / Domain SSH Address" "$BRIDGE_DOMAIN")
        CP_SSH_PORT=$(prompt_input "Enter cPanel SSH Port" "22")
        CP_SSH_USER=$(prompt_input "Enter cPanel SSH Username")
    else
        echo -e "\n${YELLOW}--- Method 2 Selected: FTP Upload ---${NC}"
        FTP_HOST=$(prompt_input "Enter cPanel FTP Host" "ftp.$BRIDGE_DOMAIN")
        FTP_USER=$(prompt_input "Enter FTP Username")
        FTP_PASS=$(prompt_input "Enter FTP Password" "" "true")
    fi

    # 1. Connect to VPS and install Xray
    echo -e "\n${BLUE}--- Part 3: Deploying Exit Node on Foreign VPS ---${NC}"
    echo -e "${YELLOW}Connecting to root@$VPS_IP:$VPS_PORT via SSH to install Xray...${NC}"
    echo -e "${GREEN}Notice: You may be asked for your VPS root SSH password below.${NC}"

    ssh -p "$VPS_PORT" -o StrictHostKeyChecking=no root@"$VPS_IP" "bash -s" <<EOF
        echo "Installing Xray-core..."
        bash -c "\$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
        
        echo "Configuring VLESS inbound on port 8080..."
        mkdir -p /usr/local/etc/xray
        cat << 'XRAY_CONF' > /usr/local/etc/xray/config.json
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
            echo "✓ Xray Exit Node is active and running beautifully!"
        else
            echo "⚠ Warning: Xray service failed to start or state is unknown."
        fi
EOF

    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ VPS SSH Deployment failed! Please double check your credentials.${NC}"
        exit 1
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

    # 3. cPanel deployment
    if [ "$METHOD" = "1" ]; then
        echo -e "\n${BLUE}--- Part 4: Connecting to cPanel via SSH ---${NC}"
        echo -e "${YELLOW}Connecting to $CP_SSH_USER@$CP_SSH_HOST:$CP_SSH_PORT...${NC}"
        echo -e "${GREEN}Notice: You may be asked for your cPanel SSH password below.${NC}"

        # Create remote folders
        ssh -p "$CP_SSH_PORT" -o StrictHostKeyChecking=no "$CP_SSH_USER@$CP_SSH_HOST" "mkdir -p ~/$APP_ROOT ~/$APP_ROOT/public"
        
        # Upload using scp
        scp -P "$CP_SSH_PORT" host/app.js host/package.json host/config.json "$CP_SSH_USER@$CP_SSH_HOST:~/$APP_ROOT/"
        scp -P "$CP_SSH_PORT" host/public/index.html host/public/style.css "$CP_SSH_USER@$CP_SSH_HOST:~/$APP_ROOT/public/"

        # Register Node application
        ssh -p "$CP_SSH_PORT" -o StrictHostKeyChecking=no "$CP_SSH_USER@$CP_SSH_HOST" "bash -s" <<EOF
            echo "Detecting Node.js interpreter version..."
            NODE_VER=\$(cloudlinux-selector interpreter --json --interpreter nodejs | grep -o '"available_versions":\[[^]]*\]' | grep -o '[0-9.]*' | tail -n1)
            if [ -z "\$NODE_VER" ]; then
                NODE_VER="20"
            fi
            
            echo "Registering application with CloudLinux Selector (Node v\$NODE_VER)..."
            cloudlinux-selector destroy --json --interpreter nodejs --app-root "$APP_ROOT" >/dev/null 2>&1
            cloudlinux-selector create --json --interpreter nodejs --version "\$NODE_VER" --app-root "$APP_ROOT" --domain "$BRIDGE_DOMAIN" --app-uri "$APP_URI" --startup-file app.js
            
            echo "Installing packages (npm install)..."
            cloudlinux-selector install-modules --json --interpreter nodejs --app-root "$APP_ROOT"
            
            echo "Restarting Node.js App..."
            cloudlinux-selector restart --json --interpreter nodejs --app-root "$APP_ROOT"
            echo "✓ App setup complete!"
EOF
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Bridge deployment on cPanel active automatically!${NC}"
        else
            echo -e "${RED}✗ Automated cPanel setup completed with warnings.${NC}"
        fi
    else
        echo -e "\n${BLUE}--- Part 4: Connecting to cPanel via FTP ---${NC}"
        echo -e "${YELLOW}Uploading files to ftp://$FTP_HOST/$APP_ROOT...${NC}"

        # Upload files using curl (FTP)
        curl -u "$FTP_USER:$FTP_PASS" --ftp-create-dirs -T host/app.js "ftp://$FTP_HOST/$APP_ROOT/app.js"
        curl -u "$FTP_USER:$FTP_PASS" --ftp-create-dirs -T host/package.json "ftp://$FTP_HOST/$APP_ROOT/package.json"
        curl -u "$FTP_USER:$FTP_PASS" --ftp-create-dirs -T host/config.json "ftp://$FTP_HOST/$APP_ROOT/config.json"
        curl -u "$FTP_USER:$FTP_PASS" --ftp-create-dirs -T host/public/index.html "ftp://$FTP_HOST/$APP_ROOT/public/index.html"
        curl -u "$FTP_USER:$FTP_PASS" --ftp-create-dirs -T host/public/style.css "ftp://$FTP_HOST/$APP_ROOT/public/style.css"

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ All files uploaded successfully via FTP!${NC}"
        else
            echo -e "${RED}✗ FTP upload failed! Make sure your credentials and host path are correct.${NC}"
            exit 1
        fi
    fi

    # Output Client links
    echo -e "\n${GREEN}============================================================${NC}"
    echo -e "${GREEN}🎉 IRANTUN TUNNEL INTEGRATION COMPLETED SUCCESSFULLY! 🎉${NC}"
    echo -e "${GREEN}============================================================${NC}"

    if [ "$METHOD" = "2" ]; then
        echo -e "\n${YELLOW}📝 MANUAL CPANEL SETUP INSTRUCTIONS:${NC}"
        echo "Please finalize the Node.js application registration in your cPanel UI:"
        echo "1) Open 'Setup Node.js App' in your cPanel dashboard."
        echo "2) Click 'Create Application'."
        echo "3) Enter the following values:"
        echo "   - Application root: $APP_ROOT"
        echo "   - Application URL: Select $BRIDGE_DOMAIN and set path to '$APP_URI'"
        echo "   - Application startup file: app.js"
        echo "4) Click 'CREATE' on the top-right corner."
        echo "5) Click the 'Run NPM Install' button to install dependencies."
    fi

    echo -e "\nReady-to-use Client Configurations:"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo -e "${GREEN}⚡ SECURED VLESS LINK (Port 443 with SSL):${NC}"
    echo -e "vless://$SECURE_UUID@$BRIDGE_DOMAIN:443?type=ws&security=tls&path=%2Fapi%2Fv1%2Fanalytics&host=$BRIDGE_DOMAIN#IranTUN_HighSpeed_VLESS"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo -e "${GREEN}⚡ UNSECURED VLESS LINK (Port 80 HTTP):${NC}"
    echo -e "vless://$SECURE_UUID@$BRIDGE_DOMAIN:80?type=ws&security=none&path=%2Fapi%2Fv1%2Fanalytics&host=$BRIDGE_DOMAIN#IranTUN_Unsecured_VLESS"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
}

main
