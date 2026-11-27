#!/bin/sh
NAMESERVER=$(grep -m1 '^nameserver' /etc/resolv.conf | awk '{print $2}')
if [ -n "$NAMESERVER" ]; then
    sed -i "s/__NAMESERVER__/$NAMESERVER/g" /etc/nginx/nginx.conf
fi
exec "$@"
