#!/bin/bash

if [[ $EUID -ne 0 ]]; then
    echo "Script ini harus dijalankan sebagai root."
    exit 1
fi

if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    USER_HOME=$HOME
fi

rollback() {
    echo "Rolling back..."
    if systemctl is-enabled --quiet gre-tc.service; then
        systemctl stop gre-tc.service
        systemctl disable gre-tc.service
        rm -f /etc/systemd/system/gre-tc.service
    fi
    if systemctl is-enabled --quiet smartroom-sys.service; then
        systemctl stop smartroom-sys.service
        systemctl disable smartroom-sys.service
        rm -f /etc/systemd/system/smartroom-sys.service
    fi
    if [ -d "$smartroom_dir" ]; then
        rm -rf "$smartroom_dir"
    fi
    systemctl daemon-reload
    echo "Rollback selesai."
    exit 1
}

trap rollback ERR

install_dependencies() {
    echo "Memeriksa dan menginstal paket yang diperlukan..."
    for pkg in ipset inotify-tools rsync; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            echo "Menginstal paket $pkg..."
            apt install -y "$pkg" 
        fi
    done
}

read -p "IP Serversec: " serversec_ip

install_dependencies
smartroom_dir="$USER_HOME/smartroom"
mkdir -p "$smartroom_dir/ips/badhost"
echo "Folder smartroom, ips, dan badhost telah dibuat di $smartroom_dir"

chown -R "$SUDO_USER:$SUDO_USER" "$smartroom_dir"
echo "Permissions untuk folder smartroom telah diatur untuk pengguna $SUDO_USER"

gre_tc_script="$smartroom_dir/gre-tc.sh"
cat <<EOL > "$gre_tc_script"
#!/bin/bash

# Mendapatkan IP lokal dan interface secara dinamis
local_ip=\$(ip route get 8.8.8.8 | awk -F"src " 'NR==1{split(\$2,a," ");print a[1]}')
interface=\$(ip route get 8.8.8.8 | awk -F"dev " 'NR==1{split(\$2,a," ");print a[1]}')

if [ -e /sys/class/net/\$interface ]; then
    ip link add tap0 type gretap remote $serversec_ip local \$local_ip dev \$interface
    ip link set tap0 up
    tc qdisc add dev \$interface handle ffff: ingress
    tc filter add dev \$interface parent ffff: protocol ip u32 match ip protocol 6 0xff action mirred egress mirror dev lo
    tc filter add dev \$interface parent ffff: protocol ip u32 match ip protocol 17 0xff action mirred egress mirror dev lo
    tc qdisc add dev \$interface handle 1: root prio
    tc filter add dev \$interface parent 1: protocol ip u32 match ip protocol 6 0xff action mirred egress mirror dev lo
    tc filter add dev \$interface parent 1: protocol ip u32 match ip protocol 17 0xff action mirred egress mirror dev lo
    tc qdisc add dev lo handle ffff: ingress
    tc filter add dev lo parent ffff: protocol ip u32 match ip protocol 6 0xff action mirred egress mirror dev tap0
    tc filter add dev lo parent ffff: protocol ip u32 match ip protocol 17 0xff action mirred egress mirror dev tap0
fi
EOL

chmod +x "$gre_tc_script"
echo "Script gre-tc.sh telah dibuat."

gre_tc_service="/etc/systemd/system/gre-tc.service"
cat <<EOL > "$gre_tc_service"
[Unit]
Description=Smartroom GRE tc Auto Start

[Service]
Type=oneshot
ExecStart=$gre_tc_script

[Install]
WantedBy=multi-user.target
EOL

echo "Service gre-tc.service telah dibuat."

script_sh="$smartroom_dir/script.sh"
cat <<EOL > "$script_sh"
#!/bin/bash

PREVIOUS_BLOCKLIST="$smartroom_dir/ips/previous_blocklist.txt"
CURRENT_BLOCKLIST_DIR="$smartroom_dir/ips/badhost"
IPTABLES="/sbin/iptables"
IPSET="/sbin/ipset"
BLOCKLIST_SET_NAME="smartroom_blacklist"
[ ! -f "\$PREVIOUS_BLOCKLIST" ] && touch "\$PREVIOUS_BLOCKLIST"

"\$IPSET" list -n | grep -q "\$BLOCKLIST_SET_NAME" || "\$IPSET" create "\$BLOCKLIST_SET_NAME" hash:ip

update_blocklist() {
    comm -13 "\$PREVIOUS_BLOCKLIST" "\$CURRENT_BLOCKLIST_DIR/badhost.txt" | while read -r IP; do
        "\$IPSET" add "\$BLOCKLIST_SET_NAME" "\$IP"
    done
    comm -23 "\$PREVIOUS_BLOCKLIST" "\$CURRENT_BLOCKLIST_DIR/badhost.txt" | while read -r IP; do
        "\$IPSET" del "\$BLOCKLIST_SET_NAME" "\$IP"
    done
    "\$IPTABLES" -C INPUT -m set --match-set "\$BLOCKLIST_SET_NAME" src -j DROP 2>/dev/null || "\$IPTABLES" -I INPUT -m set --match-set "\$BLOCKLIST_SET_NAME" src -j DROP
    cp "\$CURRENT_BLOCKLIST_DIR/badhost.txt" "\$PREVIOUS_BLOCKLIST"
}

update_blocklist

while inotifywait -r -e modify -e delete_self \$CURRENT_BLOCKLIST_DIR -e delete_self \$CURRENT_BLOCKLIST_DIR/badhost.txt; do
    update_blocklist
done
EOL

chmod +x "$script_sh"
echo "Script script.sh telah dibuat."

smartroom_sys_service="/etc/systemd/system/smartroom-sys.service"
cat <<EOL > "$smartroom_sys_service"
[Unit]
Description=Auto blacklist for Suricata Alert System (SAS)
After=network.target

[Service]
Type=simple
Restart=on-failure
RestartSec=3
ExecStart=/bin/bash $script_sh
WorkingDirectory=$smartroom_dir

[Install]
WantedBy=multi-user.target
EOL

echo "Service smartroom-sys.service telah dibuat."

systemctl daemon-reload
echo "Systemd daemon telah di-reload."

systemctl enable gre-tc.service
systemctl start gre-tc.service
systemctl enable smartroom-sys.service
systemctl start smartroom-sys.service
echo "Service gre-tc.service dan smartroom-sys.service telah di-enable dan dijalankan."

echo "Proses instalasi selesai."