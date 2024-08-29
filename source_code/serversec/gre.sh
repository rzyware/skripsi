#!/bin/bash

if [ -e /sys/class/net/eth0 ]; then
    ip link add tap0 type gretap remote 103.175.221.106 local 103.196.152.233 dev eth0
    ip link set tap0 up
fi
