#!/bin/bash

INITIAL_IP_NONLOCAL_SETTING="1"
PORTS_TO_DROP_SYN_ON_RESTART=${HAPROXY_PORTS:-"80,443"}
PORTS_TO_DROP_SYN_ON_RESTART_ARRAY=(${PORTS_TO_DROP_SYN_ON_RESTART//,/ })

function clean_up {
  echo "Sending SIGUSR1 to HAProxy..."
  kill -s SIGUSR1 $(cat /run/haproxy.pid) 2> /dev/null

  COUNTER=295
  while kill -0 $(cat /run/haproxy.pid) 2> /dev/null && [ $COUNTER -ge 0 ]; do
    echo "Waiting for HAProxy to terminate... $COUNTER seconds left"
    sleep 1
    let "COUNTER = COUNTER - 1"
  done
  if kill -0 $(cat /run/haproxy.pid) 2> /dev/null; then
    echo "Killing HAProxy"
    kill -s SIGTERM $(cat /run/haproxy.pid) 2> /dev/null
  fi
  sysctl net.ipv4.ip_nonlocal_bind | grep "net.ipv4.ip_nonlocal_bind\s*=\s*0" > /dev/null || [ "$INITIAL_IP_NONLOCAL_SETTING" -eq "1" ] || echo "Switching off ipv4.ip_nonlocal_bind" && echo "0" > /var/proc/sys/net/ipv4/ip_nonlocal_bind
  [ $(ip route show table 100 | wc -l) -ge 1 ] && echo "Deleting ip route table 100" && ip route del table 100
  echo "Deleting ip rule" && ip rule del fwmark 1 lookup 100 2> /dev/null
  echo "Flushing iptables DIVERT" && iptables -t mangle -F DIVERT 2> /dev/null
  iptables -t mangle -C PREROUTING -p tcp -m socket -j DIVERT 2> /dev/null && echo "Deleting iptables mangle rule" && iptables -t mangle -D PREROUTING -p tcp -m socket -j DIVERT
  echo "Deleting iptables DIVERT" && iptables -t mangle -X DIVERT 2> /dev/null
  echo "Done"
  exit
}

function set_up {
  sysctl net.ipv4.ip_nonlocal_bind | grep "net.ipv4.ip_nonlocal_bind\s*=\s*1" > /dev/null || echo "Setting ipv4.ip_nonlocal_bind" && INITIAL_IP_NONLOCAL_SETTING="0" && echo "1" > /var/proc/sys/net/ipv4/ip_nonlocal_bind
  echo "Creating iptables DIVERT table" && iptables -t mangle -N DIVERT 2> /dev/null
  iptables -t mangle -C PREROUTING -p tcp -m socket -j DIVERT 2> /dev/null || echo "Creating iptables DIVERT rule" && iptables -t mangle -A PREROUTING -p tcp -m socket -j DIVERT
  iptables -t mangle -C DIVERT -j MARK --set-mark 1 2> /dev/null || echo "Creating iptables mark rule" && iptables -t mangle -A DIVERT -j MARK --set-mark 1
  iptables -t mangle -C DIVERT -j ACCEPT 2> /dev/null || echo "Creating iptables rule ACCEPT for DIVERT" && iptables -t mangle -A DIVERT -j ACCEPT
  ip rule show | grep "from all fwmark 0x1 lookup 100" > /dev/null || echo "Creating ip rule for marked packets" && ip rule add fwmark 1 lookup 100
  [ $(ip route show table 100 | wc -l) -lt 1 ] && echo "Creating ip route for marked packets" && ip route add local 0.0.0.0/0 dev lo table 100
}

function reload_config {
  for PROXY_PORT in "${PORTS_TO_DROP_SYN_ON_RESTART_ARRAY[@]}"
  do
    echo "Creating iptables SYN drop rule for TCP port $PROXY_PORT"
    iptables -I INPUT -p tcp --dport $PROXY_PORT --syn -j DROP
  done
  sleep 1
  shift
  set -- "$(which haproxy)" -sf $(cat /run/haproxy.pid) "$@"
  echo "Restarting HAProxy with command '$@'"
  "$@"
  shift 3
  set -- "$(which haproxy)" "$@"
  for PROXY_PORT in "${PORTS_TO_DROP_SYN_ON_RESTART_ARRAY[@]}"
  do
    echo "Dropping iptables SYN drop rule for TCP port $PROXY_PORT"
    iptables -D INPUT -p tcp --dport $PROXY_PORT --syn -j DROP
  done
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
  echo "Starting HAProxy with command '$@'"
  "$@"
  sleep 1
  while kill -0 $(cat /run/haproxy.pid) 2> /dev/null; do
    sleep 5
  done
  clean_up
else
  echo "Executing '$@'"
  exec "$@"
fi
