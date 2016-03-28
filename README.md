# HAProxy container - with transparent TCP proxying

Docker container for HAProxy with transparent proxying

## Run the container with extra capabilities and host networking

I've tried very hard to minimise the extra capabilities this container needs to function - but these are the absolute minimum unless you want to set some of the extra host settings outside the container.

```bash
docker run [your other options] --volume=/proc/sys/net/ipv4/ip_nonlocal_bind:/var/proc/sys/net/ipv4/ip_nonlocal_bind --net=host --cap-add=SYS_MODULE --cap-add=NET_ADMIN --cap-add=NET_RAW tombull/haproxy
```

You can remove the `--volume` directive if you set the following sysctl settings on the host:

```bash
net.ipv4.ip_nonlocal_bind = 1
```

You can remove the `--cap-add=SYS_MODULE` if you ensure the following kernel module is enabled on the host:

```bash
xt_TPROXY
```

Running the container with `--net=host` and the capabilities `NET_ADMIN` and `NET_RAW` is completely unavoidable.

## When stopping the container

Always give the container enough time to shutdown. Otherwise you're going to be left with iptables rules and other stuff on your host system that you don't necessarily want.

```bash
docker stop --time=300
```

The time is in seconds and should be a little longer than your haproxy timeouts as set in your haproxy.cnf. Suggested: 300 seconds because there's a hard-coded timeout of 295 seconds in the container.

## Reloads

When HAProxy reloads, a tiny number of packets might be dropped in the process. This is well documented elsewhere around the internet. This container uses the 'drop syn packets' technique to mitigate that. There are more sophisticated techniques available which lead to lower delays on a restart (for example the Yelp qdisc technique). If you'd like to implement one of those in this container, feel free to fork. Pull requests gratefully received.

By default, the container assumes HAProxy will be listening on ports 80 & 443. If you're using HAProxy on different ports, you can alter the reload process using this environment variable when you run the container:

```bash
docker run [your other options] -e "HAPROXY_PORTS=1234,5678" [capabilities options defined above] tombull/haproxy
```
