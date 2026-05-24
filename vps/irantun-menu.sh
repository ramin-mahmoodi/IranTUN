#!/bin/bash

# IranTUN CLI Management Menu
# Designed for VPS Exit Nodes

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

XRAY_CONF="/usr/local/etc/xray/config.json"

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root (sudo irantun)${NC}"
  exit 1
fi

if [ ! -f "$XRAY_CONF" ]; then
  echo -e "${RED}Error: Xray config not found. Is IranTUN installed?${NC}"
  exit 1
fi

get_config_value() {
    # Extract values safely using awk
    UUID=$(grep '"id"' $XRAY_CONF | awk -F'"' '{print $4}' | head -1)
    PORT=$(grep '"port"' $XRAY_CONF | awk -F':' '{print $2}' | tr -d ' ,' | head -1)
    DOMAIN=$(grep '"email"' $XRAY_CONF | awk -F'@' '{print $2}' | awk -F'"' '{print $1}' | head -1)
    TLS=$(grep '"security"' $XRAY_CONF | awk -F'"' '{print $4}' | grep -v 'none' | head -1)
    if [ -z "$TLS" ]; then
        TLS="none"
    else
        TLS="tls"
    fi
}

show_config() {
    get_config_value
    echo -e "\n${BLUE}============================================================${NC}"
    echo -e "${GREEN}  IranTUN Active Configurations ${NC}"
    echo -e "${BLUE}============================================================${NC}"
    echo -e "Target Domain : ${YELLOW}$DOMAIN${NC}"
    echo -e "VPS Listen Port: ${YELLOW}$PORT${NC}"
    echo -e "Security      : ${YELLOW}$TLS${NC}"
    echo -e "Secret UUID   : ${YELLOW}$UUID${NC}"
    echo -e "\n${GREEN}⚡ VLESS CONNECTION LINK:${NC}"
    echo -e "vless://$UUID@$DOMAIN:443?type=ws&security=tls&path=%2Fapi%2Fv1%2Fanalytics&host=$DOMAIN#IranTUN_VLESS"
    echo -e "\n${GREEN}🔒 SECRET ADMIN PANEL:${NC}"
    echo -e "https://$DOMAIN?secret=$UUID"
    echo -e "${BLUE}============================================================${NC}"
    read -p "Press Enter to return to menu..."
}

change_uuid() {
    get_config_value
    echo -e "\n${YELLOW}--- Change Secret UUID ---${NC}"
    read -p "Enter new UUID (press Enter to auto-generate): " NEW_UUID
    if [ -z "$NEW_UUID" ]; then
        if command -v uuidgen >/dev/null; then
            NEW_UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
        else
            NEW_UUID=$(cat /proc/sys/kernel/random/uuid)
        fi
    fi
    
    # Replace UUID in config
    sed -i "s/\"id\": \"$UUID\"/\"id\": \"$NEW_UUID\"/g" $XRAY_CONF
    
    echo -e "Restarting Xray service..."
    systemctl restart xray
    
    echo -e "${GREEN}✓ UUID changed successfully to: $NEW_UUID${NC}"
    echo -e "${RED}⚠️ IMPORTANT: You must now log into your cPanel Web Admin Panel and update the UUID there as well, otherwise the bridge will break!${NC}"
    read -p "Press Enter to return to menu..."
}

change_port() {
    get_config_value
    echo -e "\n${YELLOW}--- Change VPS Listen Port ---${NC}"
    echo -e "Current Port: $PORT"
    read -p "Enter new Port: " NEW_PORT
    if [[ "$NEW_PORT" =~ ^[0-9]+$ ]] && [ "$NEW_PORT" -ge 1 ] && [ "$NEW_PORT" -le 65535 ]; then
        sed -i "s/\"port\": $PORT/\"port\": $NEW_PORT/g" $XRAY_CONF
        echo -e "Restarting Xray service..."
        systemctl restart xray
        echo -e "${GREEN}✓ Port changed successfully to: $NEW_PORT${NC}"
        echo -e "${RED}⚠️ IMPORTANT: Remember to update the 'VPS Port' setting in your cPanel Web Admin Panel!${NC}"
    else
        echo -e "${RED}Invalid port number.${NC}"
    fi
    read -p "Press Enter to return to menu..."
}

system_status() {
    echo -e "\n${BLUE}--- System Status ---${NC}"
    
    # Check Xray
    if systemctl is-active --quiet xray; then
        echo -e "Xray Core: ${GREEN}Active & Running${NC}"
    else
        echo -e "Xray Core: ${RED}Inactive / Error${NC}"
    fi
    
    # Check WARP
    if command -v warp-cli >/dev/null 2>&1; then
        WARP_STATUS=$(warp-cli --accept-tos status 2>/dev/null | grep 'Status' || echo "Unknown")
        if [[ "$WARP_STATUS" == *"Connected"* ]]; then
            echo -e "WARP Proxy: ${GREEN}Connected (Port 40000)${NC}"
        else
            echo -e "WARP Proxy: ${RED}Disconnected ($WARP_STATUS)${NC}"
        fi
    else
        echo -e "WARP Proxy: ${YELLOW}Not Installed${NC}"
    fi
    
    read -p "Press Enter to return to menu..."
}

restart_services() {
    echo -e "\n${BLUE}Restarting services...${NC}"
    systemctl restart xray
    echo -e "${GREEN}✓ Xray restarted${NC}"
    if command -v warp-cli >/dev/null 2>&1; then
        warp-cli --accept-tos disconnect
        sleep 1
        warp-cli --accept-tos connect
        echo -e "${GREEN}✓ WARP reconnected${NC}"
    fi
    read -p "Press Enter to return to menu..."
}

uninstall_irantun() {
    echo -e "\n${RED}!!! WARNING !!!${NC}"
    echo "This will completely remove Xray, Cloudflare WARP, and all IranTUN configurations from this VPS."
    read -p "Are you absolutely sure? (type 'yes' to confirm): " CONFIRM
    if [ "$CONFIRM" == "yes" ]; then
        echo -e "Stopping services..."
        systemctl stop xray
        systemctl disable xray
        if command -v warp-cli >/dev/null 2>&1; then
            warp-cli --accept-tos disconnect
        fi
        
        echo -e "Removing Xray..."
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove
        
        echo -e "Removing Cloudflare WARP..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get remove --purge -y cloudflare-warp
        fi
        
        echo -e "Cleaning up files..."
        rm -rf /usr/local/etc/xray
        rm -f /usr/local/bin/irantun
        
        echo -e "${GREEN}✓ IranTUN has been completely uninstalled from this VPS.${NC}"
        exit 0
    else
        echo "Uninstall cancelled."
        read -p "Press Enter to return to menu..."
    fi
}

# Main Menu Loop
while true; do
    clear
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${GREEN}      IranTUN VPS Management Console (v1.0)                 ${NC}"
    echo -e "${BLUE}============================================================${NC}"
    echo -e " [1] View Configuration & Links"
    echo -e " [2] Change Secret UUID"
    echo -e " [3] Change VPS Listen Port"
    echo -e " [4] System Status"
    echo -e " [5] Restart Services"
    echo -e " [6] Uninstall IranTUN"
    echo -e " [0] Exit"
    echo -e "${BLUE}============================================================${NC}"
    read -p "Select an option [0-6]: " OPTION

    case $OPTION in
        1) show_config ;;
        2) change_uuid ;;
        3) change_port ;;
        4) system_status ;;
        5) restart_services ;;
        6) uninstall_irantun ;;
        0) exit 0 ;;
        *) echo -e "${RED}Invalid option.${NC}"; sleep 1 ;;
    esac
done
