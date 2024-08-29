#!/bin/bash

SURICATA_DIR="/home/administrator/serversec/SELKS/docker/containers-data/suricata"

if [ ! -f "$SURICATA_DIR/logs/badhost.txt" ]; then
    touch "$SURICATA_DIR/logs/badhost.txt"
fi

extract_and_filter_ip() {
    tail -n 1 $SURICATA_DIR/logs/fast.log | grep 'Drop' | grep -oP '(\b25[0-5]|\b2[0-4][0-9]|\b[01]?[0-9][0-9]?)(\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)){3}' > /tmp/badhost.txt.tmp

    yq e '.vars.address-groups.HOME_NET' $SURICATA_DIR/etc/suricata.yaml | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" > /tmp/home_net_ip.tmp
    grep -vFf /tmp/home_net_ip.tmp /tmp/badhost.txt.tmp > /tmp/new_badhosts.tmp

    if ! grep -qFf /tmp/new_badhosts.tmp $SURICATA_DIR/logs/badhost.txt; then
        cat /tmp/new_badhosts.tmp >> $SURICATA_DIR/logs/badhost.txt
    fi
    
    rm /tmp/home_net_ip.tmp
    rm /tmp/badhost.txt.tmp
    rm /tmp/new_badhosts.tmp
}

badhost_sync() {
    rsync -az -W $SURICATA_DIR/logs/badhost.txt smartroom@103.175.221.106:~/smartroom/ips/badhost
}

inotifywait -m -e modify,create --exclude "eve.json|stats.log" "$SURICATA_DIR/logs/" |
    while read -r directory events filename; do
        sleep 1
        if [[ "$directory$filename" == "$SURICATA_DIR/logs/fast.log" ]]; then
            extract_and_filter_ip
            badhost_sync
        elif [[ "$directory$filename" == "$SURICATA_DIR/logs/badhost.txt" ]]; then
            badhost_sync
        fi
    done
