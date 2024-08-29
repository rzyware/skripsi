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

SERVERSEC_DIR="$USER_HOME/serversec"

rollback() {
    echo "Rolling back...."
    cd "$SERVERSEC_DIR/SELKS/docker/scripts" && ./cleanup.sh && cd .. && docker compose down -v
    rm -rf "$SERVERSEC_DIR" && rm -rf "$USER_HOME/skripsi"
    systemctl stop gre.service
    systemctl stop serversec-sys.service
    systemctl disable gre.service
    systemctl disable serversec-sys.service
    rm /etc/systemd/system/gre.service
    rm /etc/systemd/system/serversec-sys.service
    echo "Terjadi kegagalan. Melakukan rollback..."
    sudo apt-get remove --purge -y pfring-dkms nprobe ntopng n2disk cento 
    if [ -f /etc/ntopng/ntopng.conf ]; then
        sudo rm -f /etc/ntopng/ntopng.conf
    fi
    
    if [ -f /etc/rsyslog.d/99-suricata.conf ]; then
        sudo rm -f /etc/rsyslog.d/99-suricata.conf
    fi
    sudo systemctl restart rsyslog
    systemctl daemon-reload
    echo "Rollback selesai."
    exit 1
}

trap rollback ERR

install_dependencies() {
    echo "Memeriksa dan menginstal paket yang diperlukan..."
    for pkg in inotify-tools git rsync rsyslog chromium-browser gconf-service libasound2 libatk1.0-0 libc6 libcairo2 libcups2 libdbus-1-3 libexpat1 libfontconfig1 libgcc1 libgdk-pixbuf2.0-0 libglib2.0-0 libgtk-3-0 libnspr4 libpango-1.0-0 libpangocairo-1.0-0 libstdc++6 libx11-6 libx11-xcb1 libxcb1 libxcomposite1 libxcursor1 libxdamage1 libxfixes3 libxi6 libxrandr2 libxrender1 libxss1 libxtst6 ca-certificates fonts-liberation libappindicator1 libnss3 lsb-release xdg-utils wget libgbm-dev; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            echo "Menginstal paket $pkg..."
            apt install -y "$pkg" 
        fi
    done
}

read -p "Username server: " SMARTROOM_USER
read -p "IP server: " SMARTROOM_IP
read -p "Memori yang dialokasikan untuk Elasticsearch (ex: 2G): " MEMORY
read -p "Nomor WhatsApp untuk notifikasi alert (62): " PHONE_NUMBER

echo "Memeriksa dan membuat SSH key jika belum ada..."
if [ ! -f "$USER_HOME/.ssh/id_rsa" ]; then
    ssh-keygen -t rsa -b 2048 -f "$USER_HOME/.ssh/id_rsa" -N ""
fi

echo "Menyalin SSH key ke smartroom..."
ssh-copy-id -i "$USER_HOME/.ssh/id_rsa.pub" "$SMARTROOM_USER@$SMARTROOM_IP"

install_dependencies

install_nvm_and_node() {
    echo "Memeriksa dan menginstal nvm dan Node.js versi 21.7.3..."
    if [ ! -d "$USER_HOME/.nvm" ]; then
        echo "Menginstal nvm..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
        export NVM_DIR="$USER_HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    fi
    export NVM_DIR="$USER_HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    if ! nvm ls | grep -q "v21.7.3"; then
        echo "Menginstal Node.js versi 21.7.3..."
        nvm install 21.7.3 
    fi
    nvm use 21.7.3
    echo "done"
}

install_nvm_and_node

mkdir -p $SERVERSEC_DIR
git clone --depth 1 --no-checkout https://github.com/rzyware/skripsi && cd skripsi
git sparse-checkout set "source_code/serversec/wwebjs"
git checkout
cd .. && mv "skripsi/source_code/serversec/wwebjs" $SERVERSEC_DIR
rm -r skripsi

echo "Membuat direktori serversec..."
mkdir -p "$SERVERSEC_DIR" 
cd "$SERVERSEC_DIR" 

cat <<EOL > "$SERVERSEC_DIR/gre.sh"
#!/bin/bash

local_ip=\$(ip route get 8.8.8.8 | awk -F"src " 'NR==1{split(\$2,a," ");print a[1]}')
interface=\$(ip route get 8.8.8.8 | awk -F"dev " 'NR==1{split(\$2,a," ");print a[1]}')

if [ -e /sys/class/net/\$interface ]; then
    ip link add tap0 type gretap remote $SMARTROOM_IP local \$local_ip dev \$interface
    ip link set tap0 up
fi
EOL

chmod +x "$SERVERSEC_DIR/gre.sh"

gre_service="/etc/systemd/system/gre.service"
cat <<EOL > "$gre_service"
[Unit]
Description=Serversec GRE Auto Start

[Service]
Type=oneshot
ExecStart=$SERVERSEC_DIR/gre.sh

[Install]
WantedBy=multi-user.target
EOL

echo "Menginstal service gre..."
systemctl daemon-reload
systemctl enable gre.service
echo "Memulai service gre..."
systemctl start gre.service

echo "Mengkloning SELKS dan mengonfigurasi..."
git clone https://github.com/StamusNetworks/SELKS.git
cd SELKS/docker 
./easy-setup.sh --non-interactive -i tap0 --iA --restart-mode always --es-memory "$MEMORY"
docker compose up -d

echo "Mengedit konfigurasi YAML SELKS..."
sed -i "/^ *HOME_NET/s/\[.*\]/[$SMARTROOM_IP\/32]/" containers-data/suricata/etc/suricata.yaml 
sed -i "1,/enabled: no/s/enabled: no/enabled: yes/" containers-data/suricata/etc/selks6-addin.yaml 

cd "$SERVERSEC_DIR/SELKS/docker" && docker restart suricata

cat <<EOL > "$SERVERSEC_DIR/script.sh"
#!/bin/bash

SURICATA_DIR="$SERVERSEC_DIR/SELKS/docker/containers-data/suricata"

if [ ! -f "\$SURICATA_DIR/logs/badhost.txt" ]; then
    touch "\$SURICATA_DIR/logs/badhost.txt"
fi

extract_and_filter_ip() {
    tail -n 1 \$SURICATA_DIR/logs/fast.log | grep 'Drop' | grep -oP '(\b25[0-5]|\b2[0-4][0-9]|\b[01]?[0-9][0-9]?)(\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)){3}' > /tmp/badhost.txt.tmp

    yq e '.vars.address-groups.HOME_NET' \$SURICATA_DIR/etc/suricata.yaml | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" > /tmp/home_net_ip.tmp
    grep -vFf /tmp/home_net_ip.tmp /tmp/badhost.txt.tmp > /tmp/new_badhosts.tmp

    if ! grep -qFf /tmp/new_badhosts.tmp \$SURICATA_DIR/logs/badhost.txt; then
        cat /tmp/new_badhosts.tmp >> \$SURICATA_DIR/logs/badhost.txt
    fi

    rm /tmp/home_net_ip.tmp
    rm /tmp/badhost.txt.tmp
    rm /tmp/new_badhosts.tmp
}

badhost_sync() {
    rsync -az -W \$SURICATA_DIR/logs/badhost.txt $SMARTROOM_USER@$SMARTROOM_IP:~/smartroom/ips/badhost
}

inotifywait -m -e modify,create --exclude "eve.json|stats.log" "\$SURICATA_DIR/logs/" |
    while read -r directory events filename; do
        sleep 1
        if [[ "\$directory\$filename" == "\$SURICATA_DIR/logs/fast.log" ]]; then
            extract_and_filter_ip
            badhost_sync
        elif [[ "\$directory\$filename" == "\$SURICATA_DIR/logs/badhost.txt" ]]; then
            badhost_sync
        fi
    done
EOL

chmod +x "$SERVERSEC_DIR/script.sh"

echo "Membuat file .env di direktori wwebjs..."
cat <<EOL > "$SERVERSEC_DIR/wwebjs/.env"
SERVICE_LOGDIR=$SERVERSEC_DIR/SELKS/docker/containers-data/suricata/logs
WHATSAPP_PHONE=$PHONE_NUMBER
BASH_PATH=/bin/bash
BASH_SCRIPT_PATH=$SERVERSEC_DIR/script.sh
EOL

echo "Menginstal dependensi npm dan memulai service..."
cd "$SERVERSEC_DIR/wwebjs" 
npm install 

echo "Memulai script.sh..."
nohup $USER_HOME/.nvm/versions/node/v21.7.3/bin/node "$SERVERSEC_DIR/script.sh" > "$SERVERSEC_DIR/script.log" 2>&1 &
sleep 5

if pgrep -f script.sh > /dev/null; then
    echo "Script script.sh berhasil dijalankan."
else
    echo "Gagal menjalankan script script.sh. Aborting."
fi

serversec_sys_service="/etc/systemd/system/serversec-sys.service"
cat <<EOL > "$serversec_sys_service"
[Unit]
Description=Serversec System
After=network.target

[Service]
Type=simple
Restart=on-failure
RestartSec=3
ExecStart=$USER_HOME/.nvm/versions/node/v21.7.3/bin/node $SERVERSEC_DIR/wwebjs/checker.js
WorkingDirectory=$SERVERSEC_DIR/wwebjs

[Install]
WantedBy=multi-user.target
EOL

echo "Menginstal service serversec-sys..."

systemctl daemon-reload
systemctl enable serversec-sys.service


echo "Memulai serversec-sys..."
systemctl start serversec-sys.service

if systemctl is-active --quiet serversec-sys.service; then
    echo "Service serversec-sys berhasil dijalankan."
else
    echo "Gagal menjalankan service serversec-sys. Aborting."
fi

apt-get install software-properties-common wget && add-apt-repository -y universe
wget https://packages.ntop.org/apt-stable/$(lsb_release -sr)/all/apt-ntop-stable.deb
chown _apt apt-ntop-stable.deb
apt install ./apt-ntop-stable.deb
apt-get clean all && apt-get update && apt-get install -y pfring-dkms nprobe ntopng n2disk cento 
rm apt-ntop-stable.deb

DOCKER0_IP=$(ip addr show docker0 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)

if [ ! -d /etc/ntopng ]; then
    sudo mkdir -p /etc/ntopng
fi

bash -c "cat > /etc/ntopng/ntopng.conf << EOL
# ntopng configuration

-i=syslog://$DOCKER0_IP:9999
-i=tap0
EOL"

bash -c "echo '\$template suricata_raw,\"%msg%\\n\"

module(load=\"imfile\")

input(type=\"imfile\"
      File=\"$SERVERSEC_DIR/SELKS/docker/containers-data/suricata/logs/eve.json\"
      Tag=\"suricata-log\"
      Severity=\"alert\"
      Facility=\"local7\")

if \$syslogtag == 'suricata-log' then {
    action(type=\"omfwd\"
          Target=\"$DOCKER0_IP\"
          Port=\"9999\"
          Protocol=\"tcp\"
          Template=\"suricata_raw\")
}
' > /etc/rsyslog.d/99-suricata.conf"

sudo systemctl restart rsyslog
sudo systemctl restart ntopng

echo "Instalasi serversec selesai. Semua service sudah dijalankan."

exit 0