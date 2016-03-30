FROM tombull/haproxy:alpine-withconfd

RUN apk add --no-cache --update -t deps iptables \
    && apk add --update bash \
    && apk del --purge deps \
    && rm -rf /tmp/* /var/cache/apk/*

COPY docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["haproxy", "-f", "/usr/local/etc/haproxy/haproxy.cfg"]
