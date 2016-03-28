#!/bin/bash

INITIAL_IP_NONLOCAL_SETTING="1"
PORTS_TO_DROP_SYN_ON_RESTART=${HAPROXY_PORTS:-"80,443"}

function clean_up {
  kill -s SIGUSR1 $(cat /run/haproxy.pid) 2> /dev/null
  COUNTER = 0
  while kill -0 $(cat /run/haproxy.pid) 2> /dev/null && [ $COUNTER -lt 295 ]; do
    sleep 1
  done
  kill -s SIGTERM $(cat /run/haproxy.pid) 2> /dev/null
  sysctl net.ipv4.ip_nonlocal_bind | grep "net.ipv4.ip_nonlocal_bind\s*=\s*0" > /dev/null || [ "$INITIAL_IP_NONLOCAL_SETTING" -eq "1" ] || echo "0" > /var/proc/sys/net/ipv4/ip_nonlocal_bind
  [ $(ip route show table 100 | wc -l) -ge 1 ] && ip route del table 100
  ip rule del fwmark 1 lookup 100 2> /dev/null
  iptables -t mangle -F DIVERT 2> /dev/null
  iptables -t mangle -C PREROUTING -p tcp -m socket -j DIVERT 2> /dev/null && iptables -t mangle -D PREROUTING -p tcp -m socket -j DIVERT
  iptables -t mangle -X DIVERT 2> /dev/null
  exit
}

function set_up {
  sysctl net.ipv4.ip_nonlocal_bind | grep "net.ipv4.ip_nonlocal_bind\s*=\s*1" > /dev/null || INITIAL_IP_NONLOCAL_SETTING="0"; echo "1" > /var/proc/sys/net/ipv4/ip_nonlocal_bind
  iptables -t mangle -N DIVERT 2> /dev/null
  iptables -t mangle -C PREROUTING -p tcp -m socket -j DIVERT 2> /dev/null || iptables -t mangle -A PREROUTING -p tcp -m socket -j DIVERT
  iptables -t mangle -C DIVERT -j MARK --set-mark 1 2> /dev/null || iptables -t mangle -A DIVERT -j MARK --set-mark 1
  iptables -t mangle -C DIVERT -j ACCEPT 2> /dev/null || iptables -t mangle -A DIVERT -j ACCEPT
  ip rule show | grep "from all fwmark 0x1 lookup 100" > /dev/null || ip rule add fwmark 1 lookup 100
  [ $(ip route show table 100 | wc -l) -lt 1 ] && ip route add local 0.0.0.0/0 dev lo table 100
}

function reload_config {
  iptables -I INPUT -p tcp --dports $PORTS_TO_DROP_SYN_ON_RESTART --syn -j DROP
  sleep 1
  shift
  set -- "$(which haproxy)" -sf $(cat /run/haproxy.pid) "$@"
  "$@"
  shift 3
  set -- "$(which haproxy)" "$@"
  iptables -D INPUT -p tcp --dport $PORTS_TO_DROP_SYN_ON_RESTART --syn -j DROP
}

trap clean_up SIGINT SIGTERM
trap reload_config SIGHUP SIGUSR2

# first arg is `-f` or `--some-option`
if [ "${1#-}" != "$1" ]; then
	set -- haproxy "$@"
fi

if [ "$1" = 'haproxy' ]; then
	shift # "haproxy"
	set -- "$(which haproxy)" -D -p /run/haproxy.pid "$@"
  set_up
  "$@"
  sleep 1
  while kill -0 $(cat /run/haproxy.pid) 2> /dev/null; do
    sleep 5
  done
  clean_up
else
  exec "$@"
fi
