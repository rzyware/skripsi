#!/bin/bash

PREVIOUS_BLOCKLIST="/home/smartroom/smartroom/ips/previous_blocklist.txt"
CURRENT_BLOCKLIST_DIR="/home/smartroom/smartroom/ips/badhost"
IPTABLES="/sbin/iptables"
IPSET="/sbin/ipset"
BLOCKLIST_SET_NAME="smartroom_blacklist"
[ ! -f "$PREVIOUS_BLOCKLIST" ] && touch "$PREVIOUS_BLOCKLIST"

"$IPSET" list -n | grep -q "$BLOCKLIST_SET_NAME" || "$IPSET" create "$BLOCKLIST_SET_NAME" hash:ip

update_blocklist() {
    comm -13 "$PREVIOUS_BLOCKLIST" "$CURRENT_BLOCKLIST_DIR/badhost.txt" | while read -r IP; do
        "$IPSET" add "$BLOCKLIST_SET_NAME" "$IP"
    done
    comm -23 "$PREVIOUS_BLOCKLIST" "$CURRENT_BLOCKLIST_DIR/badhost.txt" | while read -r IP; do
        "$IPSET" del "$BLOCKLIST_SET_NAME" "$IP"
    done
    "$IPTABLES" -C INPUT -m set --match-set "$BLOCKLIST_SET_NAME" src -j DROP 2>/dev/null || "$IPTABLES" -I INPUT -m set --match-set "$BLOCKLIST_SET_NAME" src -j DROP
    cp "$CURRENT_BLOCKLIST_DIR/badhost.txt" "$PREVIOUS_BLOCKLIST"
}

update_blocklist

while inotifywait -r -e modify -e delete_self $CURRENT_BLOCKLIST_DIR -e delete_self $CURRENT_BLOCKLIST_DIR/badhost.txt; do
    update_blocklist
done
