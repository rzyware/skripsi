#!/bin/bash

if [ -e /sys/class/net/eth0 ]; then
    ip link add tap0 type gretap remote 103.196.152.233 local 103.175.221.106 dev eth0
    ip link set tap0 up
    tc qdisc add dev eth0 handle ffff: ingress
    tc filter add dev eth0 parent ffff: protocol ip u32 match ip protocol 6 0xff action mirred egress mirror dev lo
    tc filter add dev eth0 parent ffff: protocol ip u32 match ip protocol 17 0xff action mirred egress mirror dev lo
    tc qdisc add dev eth0 handle 1: root prio
    tc filter add dev eth0 parent 1: protocol ip u32 match ip protocol 6 0xff action mirred egress mirror dev lo
    tc filter add dev eth0 parent 1: protocol ip u32 match ip protocol 17 0xff action mirred egress mirror dev lo
    tc qdisc add dev lo handle ffff: ingress
    tc filter add dev lo parent ffff: protocol ip u32 match ip protocol 6 0xff action mirred egress mirror dev tap0
    tc filter add dev lo parent ffff: protocol ip u32 match ip protocol 17 0xff action mirred egress mirror dev tap0
fi
