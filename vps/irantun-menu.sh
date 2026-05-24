#!/bin/bash

# IranTUN CLI Management Menu - Multi-User Edition
# Designed for VPS Exit Nodes

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

if ! command -v jq >/dev/null 2>&1; then
  echo -e "${RED}Error: 'jq' is not installed. Please install jq to use the multi-user manager.${NC}"
  echo "Debian/Ubuntu: apt-get install jq"
  echo "CentOS/RHEL: yum install jq"
  exit 1
fi

# Extract common bridge settings
DOMAIN=$(jq -r '.inbounds[0].settings.clients[0].email' $XRAY_CONF | cut -d'@' -f2)
PORT=$(jq -r '.inbounds[0].port' $XRAY_CONF)
TLS_SETTING=$(jq -r '.inbounds[0].streamSettings.security' $XRAY_CONF)
DOMAINS_FILE="/usr/local/etc/xray/domains.txt"

if [ ! -f "$DOMAINS_FILE" ]; then
    echo "$DOMAIN" > "$DOMAINS_FILE"
fi

generate_vless_link() {
    local uuid=$1
    local email=$2
    local domain=$3
    local tls=$4
    local name=$(echo "$email" | cut -d'@' -f1)
    
    if [ "$tls" == "tls" ]; then
        echo "vless://$uuid@$domain:443?type=ws&security=tls&path=%2Fapi%2Fv1%2Fanalytics&host=$domain#IranTUN_$name"
    else
        echo "vless://$uuid@$domain:80?type=ws&security=none&path=%2Fapi%2Fv1%2Fanalytics&host=$domain#IranTUN_${name}_Unsecured"
    fi
}

list_users() {
    echo -e "\n${BLUE}============================================================${NC}"
    echo -e "${GREEN}  IranTUN Active Users & Links ${NC}"
    echo -e "${BLUE}============================================================${NC}"
    
    local num_clients=$(jq '.inbounds[0].settings.clients | length' $XRAY_CONF)
    
    if [ "$num_clients" -eq 0 ]; then
        echo -e "${RED}No users found.${NC}"
    else
        for ((i=0; i<$num_clients; i++)); do
            local client_uuid=$(jq -r ".inbounds[0].settings.clients[$i].id" $XRAY_CONF)
            local client_email=$(jq -r ".inbounds[0].settings.clients[$i].email" $XRAY_CONF)
            local client_name=$(echo "$client_email" | cut -d'@' -f1)
            
            echo -e "${YELLOW}[User $((i+1))] Name:${NC} $client_name"
            echo -e "${CYAN}UUID:${NC} $client_uuid"
            while IFS= read -r d || [ -n "$d" ]; do
                generate_vless_link "$client_uuid" "$client_email" "$d" "$TLS_SETTING"
            done < "$DOMAINS_FILE"
            echo -e "------------------------------------------------------------"
        done
    fi
    echo -e "${BLUE}============================================================${NC}"
    read -p "Press Enter to return to menu..."
}

add_user() {
    echo -e "\n${YELLOW}--- Add New User ---${NC}"
    read -p "Enter username (no spaces, e.g. 'Ali' or 'User2'): " NEW_USER
    if [ -z "$NEW_USER" ]; then
        echo -e "${RED}Username cannot be empty.${NC}"
        read -p "Press Enter to return..."
        return
    fi
    
    # Remove spaces and special chars
    NEW_USER=$(echo "$NEW_USER" | tr -dc '[:alnum:]_')
    
    # Check if user already exists
    local exists=$(jq -r ".inbounds[0].settings.clients[].email" $XRAY_CONF | grep -c "^${NEW_USER}@")
    if [ "$exists" -gt 0 ]; then
        echo -e "${RED}Error: User '$NEW_USER' already exists!${NC}"
        read -p "Press Enter to return..."
        return
    fi
    
    # Generate UUID
    if command -v uuidgen >/dev/null; then
        NEW_UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
    else
        NEW_UUID=$(cat /proc/sys/kernel/random/uuid)
    fi
    
    local NEW_EMAIL="${NEW_USER}@${DOMAIN}"
    
    # Use jq to append a new client
    # Create a temp file
    local TMP_CONF=$(mktemp)
    jq ".inbounds[0].settings.clients += [{\"id\": \"$NEW_UUID\", \"level\": 0, \"email\": \"$NEW_EMAIL\"}]" $XRAY_CONF > $TMP_CONF
    
    if [ $? -eq 0 ]; then
        cat $TMP_CONF > $XRAY_CONF
        rm -f $TMP_CONF
        systemctl restart xray
        echo -e "${GREEN}✓ User '$NEW_USER' added successfully!${NC}"
        echo -e "\n${GREEN}⚡ Connection Links:${NC}"
        while IFS= read -r d || [ -n "$d" ]; do
            generate_vless_link "$NEW_UUID" "$NEW_EMAIL" "$d" "$TLS_SETTING"
        done < "$DOMAINS_FILE"
    else
        echo -e "${RED}Error adding user.${NC}"
        rm -f $TMP_CONF
    fi
    
    echo -e "\n"
    read -p "Press Enter to return to menu..."
}

remove_user() {
    echo -e "\n${YELLOW}--- Remove User ---${NC}"
    local num_clients=$(jq '.inbounds[0].settings.clients | length' $XRAY_CONF)
    
    if [ "$num_clients" -eq 0 ]; then
        echo -e "${RED}No users found.${NC}"
        read -p "Press Enter to return..."
        return
    fi
    
    echo "Available users:"
    for ((i=0; i<$num_clients; i++)); do
        local client_email=$(jq -r ".inbounds[0].settings.clients[$i].email" $XRAY_CONF)
        local client_name=$(echo "$client_email" | cut -d'@' -f1)
        echo -e "  [$i] $client_name"
    done
    
    read -p "Enter the number of the user to remove (or 'q' to cancel): " DEL_IDX
    
    if [ "$DEL_IDX" == "q" ] || [ -z "$DEL_IDX" ]; then
        return
    fi
    
    if [[ "$DEL_IDX" =~ ^[0-9]+$ ]] && [ "$DEL_IDX" -lt "$num_clients" ]; then
        local target_name=$(jq -r ".inbounds[0].settings.clients[$DEL_IDX].email" $XRAY_CONF | cut -d'@' -f1)
        read -p "Are you sure you want to delete '$target_name'? (y/n) " CONFIRM
        if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
            local TMP_CONF=$(mktemp)
            jq "del(.inbounds[0].settings.clients[$DEL_IDX])" $XRAY_CONF > $TMP_CONF
            if [ $? -eq 0 ]; then
                cat $TMP_CONF > $XRAY_CONF
                rm -f $TMP_CONF
                systemctl restart xray
                echo -e "${GREEN}✓ User '$target_name' deleted successfully.${NC}"
            else
                echo -e "${RED}Error deleting user.${NC}"
                rm -f $TMP_CONF
            fi
        else
            echo "Cancelled."
        fi
    else
        echo -e "${RED}Invalid user number.${NC}"
    fi
    
    read -p "Press Enter to return..."
}

change_port() {
    echo -e "\n${YELLOW}--- Change VPS Listen Port ---${NC}"
    echo -e "Current Port: $PORT"
    read -p "Enter new Port: " NEW_PORT
    if [[ "$NEW_PORT" =~ ^[0-9]+$ ]] && [ "$NEW_PORT" -ge 1 ] && [ "$NEW_PORT" -le 65535 ]; then
        local TMP_CONF=$(mktemp)
        jq ".inbounds[0].port = $NEW_PORT" $XRAY_CONF > $TMP_CONF
        if [ $? -eq 0 ]; then
            cat $TMP_CONF > $XRAY_CONF
            rm -f $TMP_CONF
            systemctl restart xray
            echo -e "${GREEN}✓ Port changed successfully to: $NEW_PORT${NC}"
            echo -e "${RED}⚠️ IMPORTANT: Remember to update the 'VPS Port' setting in your cPanel Web Admin Panel!${NC}"
        else
            echo -e "${RED}Error changing port.${NC}"
            rm -f $TMP_CONF
        fi
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
    
    # Check WARP (WireProxy)
    if systemctl is-active --quiet wireproxy; then
        echo -e "WARP Proxy: ${GREEN}Connected (WireProxy on Port 40000)${NC}"
    else
        echo -e "WARP Proxy: ${RED}Disconnected / Not Installed${NC}"
    fi
    
    read -p "Press Enter to return to menu..."
}

restart_services() {
    echo -e "\n${BLUE}Restarting services...${NC}"
    systemctl restart xray
    echo -e "${GREEN}✓ Xray restarted${NC}"
    if systemctl list-unit-files | grep -q wireproxy.service; then
        systemctl restart wireproxy
        echo -e "${GREEN}✓ WireProxy (WARP) restarted${NC}"
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
        if systemctl list-unit-files | grep -q wireproxy.service; then
            systemctl stop wireproxy
            systemctl disable wireproxy
        fi
        
        echo -e "Removing Xray..."
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove
        
        echo -e "Removing WireProxy..."
        rm -f /usr/local/bin/wireproxy
        rm -f /usr/local/bin/wgcf
        rm -rf /usr/local/etc/wireproxy
        rm -f /etc/systemd/system/wireproxy.service
        systemctl daemon-reload
        
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

manage_domains() {
    while true; do
        clear
        echo -e "${BLUE}============================================================${NC}"
        echo -e "${GREEN}      cPanel Host Domains Management      ${NC}"
        echo -e "${BLUE}============================================================${NC}"
        echo "Active Domains for Link Generation:"
        local idx=1
        while IFS= read -r d || [ -n "$d" ]; do
            if [ -n "$d" ]; then
                echo -e "  [$idx] $d"
                ((idx++))
            fi
        done < "$DOMAINS_FILE"
        echo -e "------------------------------------------------------------"
        echo -e " [1] Add New Domain"
        echo -e " [2] Remove Domain"
        echo -e " [0] Back to Main Menu"
        read -p "Select an option: " DOM_OPT
        
        case $DOM_OPT in
            1)
                read -p "Enter new domain (e.g. host2.com): " NEW_DOM
                if [ -n "$NEW_DOM" ]; then
                    # basic validation
                    NEW_DOM=$(echo "$NEW_DOM" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
                    if grep -q "^${NEW_DOM}$" "$DOMAINS_FILE"; then
                        echo -e "${RED}Domain already exists!${NC}"
                    else
                        echo "$NEW_DOM" >> "$DOMAINS_FILE"
                        echo -e "${GREEN}Domain added.${NC}"
                    fi
                fi
                sleep 1
                ;;
            2)
                read -p "Enter the number of the domain to remove: " DEL_DOM_IDX
                if [[ "$DEL_DOM_IDX" =~ ^[0-9]+$ ]] && [ "$DEL_DOM_IDX" -ge 1 ] && [ "$DEL_DOM_IDX" -lt "$idx" ]; then
                    local target_dom=$(sed -n "${DEL_DOM_IDX}p" "$DOMAINS_FILE")
                    # Make sure we don't delete the last domain
                    if [ "$idx" -le 2 ]; then
                        echo -e "${RED}Cannot remove the last domain. Please add another one first.${NC}"
                    else
                        sed -i "${DEL_DOM_IDX}d" "$DOMAINS_FILE"
                        echo -e "${GREEN}Domain '$target_dom' removed.${NC}"
                    fi
                else
                    echo -e "${RED}Invalid selection.${NC}"
                fi
                sleep 1
                ;;
            0) break ;;
            *) echo -e "${RED}Invalid option.${NC}"; sleep 1 ;;
        esac
    done
}

# Main Menu Loop
while true; do
    clear
    # Re-fetch variables to ensure they are up to date
    DOMAIN=$(jq -r '.inbounds[0].settings.clients[0].email' $XRAY_CONF | cut -d'@' -f2)
    PORT=$(jq -r '.inbounds[0].port' $XRAY_CONF)
    TLS_SETTING=$(jq -r '.inbounds[0].streamSettings.security' $XRAY_CONF)

    echo -e "${BLUE}============================================================${NC}"
    echo -e "${GREEN}      IranTUN VPS User Management Console (Multi-User)      ${NC}"
    echo -e "${BLUE}============================================================${NC}"
    echo -e " [1] View All Users & VLESS Links"
    echo -e " [2] Add New User"
    echo -e " [3] Remove User"
    echo -e " [4] Manage cPanel Domains (Multi-Host)"
    echo -e " [5] Change VPS Listen Port"
    echo -e " [6] System Status"
    echo -e " [7] Restart Services"
    echo -e " [8] Uninstall IranTUN"
    echo -e " [0] Exit"
    echo -e "${BLUE}============================================================${NC}"
    read -p "Select an option [0-8]: " OPTION

    case $OPTION in
        1) list_users ;;
        2) add_user ;;
        3) remove_user ;;
        4) manage_domains ;;
        5) change_port ;;
        6) system_status ;;
        7) restart_services ;;
        8) uninstall_irantun ;;
        0) exit 0 ;;
        *) echo -e "${RED}Invalid option.${NC}"; sleep 1 ;;
    esac
done
