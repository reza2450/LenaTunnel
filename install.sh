#!/bin/bash

# ---------------- INSTALL DEPENDENCIES ----------------
echo "[*] Installing prerequisites (iproute2, net-tools, grep, awk, jq, curl)..."
sudo apt update -y >/dev/null 2>&1
sudo apt install -y iproute2 net-tools grep awk sudo iputils-ping jq curl haproxy >/dev/null 2>&1
sudo apt-get install -y jq
sudo apt install -y haproxy
# ---------------- COLORS ----------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ---------------- FUNCTIONS ----------------

check_core_status() {
    ip link show | grep -q 'vxlan' && echo "Active" || echo "Inactive"
}

Lena_menu() {
    clear
    SERVER_IP=$(hostname -I | awk '{print $1}')
    SERVER_COUNTRY=$(curl -sS "http://ip-api.com/json/$SERVER_IP" | jq -r '.country')
    SERVER_ISP=$(curl -sS "http://ip-api.com/json/$SERVER_IP" | jq -r '.isp')

    echo "+-----------------------------------------------------------------------------+"
    echo "| _                      										|"
    echo "|| |                     										|"
    echo "|| |     ___ _ __   __ _ 										|"
    echo "|| |    / _ \ '_ \ / _  |										|"
    echo "|| |___|  __/ | | | (_| |										|"
    echo "|\_____/\___|_| |_|\__,_|	V1.0.2 Beta				            |" 
    echo "+-----------------------------------------------------------------------------+"    
    echo -e "| Telegram Channel : ${MAGENTA}@AminiDev ${NC}| Version : ${GREEN} 1.0.2 Beta ${NC} "
    echo "+-----------------------------------------------------------------------------+"      
    echo -e "|${GREEN}Server Country    |${NC} $SERVER_COUNTRY"
    echo -e "|${GREEN}Server IP         |${NC} $SERVER_IP"
    echo -e "|${GREEN}Server ISP        |${NC} $SERVER_ISP"
    echo "+-----------------------------------------------------------------------------+"
    echo -e "|${YELLOW}Please choose an option:${NC}"
    echo "+-----------------------------------------------------------------------------+"
    echo -e "1- Install new tunnel"
    echo -e "2- Uninstall tunnel(s)"
    echo -e "3- Install BBR"
    echo -e "4- Apply network optimizations"
    echo "+-----------------------------------------------------------------------------+"
    echo -e "\033[0m"
}

uninstall_all_vxlan() {
    echo "[!] Deleting all VXLAN interfaces and cleaning up..."
    for i in $(ip -d link show | grep -o 'vxlan[0-9]\+'); do
        ip link del $i 2>/dev/null
    done
    rm -f /usr/local/bin/vxlan_bridge.sh /etc/ping_vxlan.sh
    systemctl disable --now vxlan-tunnel.service 2>/dev/null
    rm -f /etc/systemd/system/vxlan-tunnel.service
    systemctl daemon-reload
    echo "[+] All VXLAN tunnels deleted."
}

install_bbr() {
    echo "[*] Enabling BBR and fast queue..."
    modprobe tcp_bbr 2>/dev/null
    cat <<EOF >/etc/sysctl.d/99-lena-bbr.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    sysctl -p /etc/sysctl.d/99-lena-bbr.conf >/dev/null
    echo "[+] BBR has been enabled."
}

apply_net_optimizations() {
    echo "[*] Applying additional network optimizations..."
    cat <<EOF >/etc/sysctl.d/99-lena-opt.conf
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_mtu_probing=1
EOF
    sysctl -p /etc/sysctl.d/99-lena-opt.conf >/dev/null
    echo "[+] Network optimizations applied."
}

install_haproxy_and_configure() {
    echo "[*] Configuring HAProxy..."

    # Default HAProxy config file
    local CONFIG_FILE="/etc/haproxy/haproxy.cfg"
    local BACKUP_FILE="/etc/haproxy/haproxy.cfg.bak"

    # Backup old config
    [ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "$BACKUP_FILE"

    # Write base config
    cat <<EOL > "$CONFIG_FILE"
global
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    mode    tcp
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000
EOL

    read -p "Enter ports (comma-separated): " user_ports
    local local_ip=$(hostname -I | awk '{print $1}')

    IFS=',' read -ra ports <<< "$user_ports"

    for port in "${ports[@]}"; do
        cat <<EOL >> "$CONFIG_FILE"

frontend frontend_$port
    bind *:$port
    default_backend backend_$port

backend backend_$port
    server server1 $local_ip:$port check
EOL
    done

    # Validate haproxy config
    if haproxy -c -f "$CONFIG_FILE"; then
        echo "[*] Restarting HAProxy service..."
        systemctl restart haproxy
        echo -e "${GREEN}HAProxy configured and restarted successfully.${NC}"
    else
        echo -e "${YELLOW}Warning: HAProxy configuration is invalid!${NC}"
    fi
}

# ---------------- MAIN ----------------
while true; do
    Lena_menu
    read -p "Enter your choice [1-4]: " main_action
    case $main_action in
        1)
            break
            ;;
        2)
            uninstall_all_vxlan
            read -p "Press Enter to return to menu..."
            ;;
        3)
            install_bbr
            read -p "Press Enter to return to menu..."
            ;;
        4)
            apply_net_optimizations
            read -p "Press Enter to return to menu..."
            ;;
        *)
            echo "[x] Invalid option. Try again."
            sleep 1
            ;;
    esac
done

# Check if ip command is available
if ! command -v ip >/dev/null 2>&1; then
    echo "[x] iproute2 is not installed. Aborting."
    exit 1
fi

# ------------- VARIABLES --------------
VNI=88
VXLAN_IF="vxlan${VNI}"

# --------- Choose Server Role ----------
echo "Choose server role:"
echo "1- Iran"
echo "2- Kharej"
read -p "Enter choice (1/2): " role_choice

if [[ "$role_choice" == "1" ]]; then
    read -p "Enter IRAN IP: " IRAN_IP
    read -p "Enter Kharej IP: " KHAREJ_IP

    # Port validation loop
    while true; do
        read -p "Tunnel port (1 ~ 64435): " DSTPORT
        if [[ $DSTPORT =~ ^[0-9]+$ ]] && (( DSTPORT >= 1 && DSTPORT <= 64435 )); then
            break
        else
            echo "Invalid port. Try again."
        fi
    done

    read -p "Should port forwarding be done automatically? (It is done with haproxy tool) [1-yes, 2-no]: " haproxy_choice

    if [[ "$haproxy_choice" == "1" ]]; then
        install_haproxy_and_configure
    else
        ipv4_local=$(hostname -I | awk '{print $1}')
        echo "IRAN Server setup complete."
        echo -e "####################################"
        echo -e "# Your IPv4 :                      #"
        echo -e "#  30.0.0.1                     #"
        echo -e "####################################"
    fi

    VXLAN_IP="30.0.0.1/24"
    REMOTE_IP=$KHAREJ_IP

elif [[ "$role_choice" == "2" ]]; then
    read -p "Enter IRAN IP: " IRAN_IP
    read -p "Enter Kharej IP: " KHAREJ_IP

    # Port validation loop
    while true; do
        read -p "Tunnel port (1 ~ 64435): " DSTPORT
        if [[ $DSTPORT =~ ^[0-9]+$ ]] && (( DSTPORT >= 1 && DSTPORT <= 64435 )); then
            break
        else
            echo "Invalid port. Try again."
        fi
    done

    ipv4_local=$(hostname -I | awk '{print $1}')
    echo "Kharej Server setup complete."
    echo -e "####################################"
    echo -e "# Your IPv4 :                      #"
    echo -e "#  30.0.0.2                        #"
    echo -e "####################################"

    VXLAN_IP="30.0.0.2/24"
    REMOTE_IP=$IRAN_IP

else
    echo "[x] Invalid role selected."
    exit 1
fi

# Detect default interface
INTERFACE=$(ip route get 1.1.1.1 | awk '{print $5}' | head -n1)
echo "Detected main interface: $INTERFACE"

# ------------ Setup VXLAN --------------
echo "[+] Creating VXLAN interface..."
ip link add $VXLAN_IF type vxlan id $VNI local $(hostname -I | awk '{print $1}') remote $REMOTE_IP dev $INTERFACE dstport $DSTPORT nolearning

echo "[+] Assigning IP $VXLAN_IP to $VXLAN_IF"
ip addr add $VXLAN_IP dev $VXLAN_IF
ip link set $VXLAN_IF up

echo "[+] Adding iptables rules"
iptables -I INPUT 1 -p udp --dport $DSTPORT -j ACCEPT
iptables -I INPUT 1 -s $REMOTE_IP -j ACCEPT
iptables -I INPUT 1 -s ${VXLAN_IP%/*} -j ACCEPT

# ---------------- CREATE SYSTEMD SERVICE ----------------
echo "[+] Creating systemd service for VXLAN..."

cat <<EOF > /usr/local/bin/vxlan_bridge.sh
#!/bin/bash
ip link add $VXLAN_IF type vxlan id $VNI local $(hostname -I | awk '{print $1}') remote $REMOTE_IP dev $INTERFACE dstport $DSTPORT nolearning
ip addr add $VXLAN_IP dev $VXLAN_IF
ip link set $VXLAN_IF up
EOF

chmod +x /usr/local/bin/vxlan_bridge.sh

cat <<EOF > /etc/systemd/system/vxlan-tunnel.service
[Unit]
Description=VXLAN Tunnel Interface
After=network.target

[Service]
ExecStart=/usr/local/bin/vxlan_bridge.sh
Type=oneshot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

chmod 644 /etc/systemd/system/vxlan-tunnel.service
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable vxlan-tunnel.service
systemctl start vxlan-tunnel.service

echo -e "\n${GREEN}[✓] VXLAN tunnel service enabled to run on boot.${NC}"

echo "[✓] VXLAN tunnel setup completed successfully."
