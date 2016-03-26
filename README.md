# HAProxy container

Docker container for HAProxy with transparent proxying

## Host OS Settings

There are a number of host settings you'll need.

### Enable kernel modules

- xt_TPROXY must be enabled

### Switch sysctl settings

```
net.ipv4.ip_forward = 1
net.ipv4.ip_nonlocal_bind = 1
```

### Run the container with privileged settings

```bash
docker run [other options] --cap-add=NET_ADMIN --cap-add=NET_RAW tombull/haproxy
```
