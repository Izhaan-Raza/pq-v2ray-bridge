#!/usr/bin/env bash

sudo mkdir -p /etc/ssl/certs /etc/ssl/private

sudo /opt/openssl/bin/openssl req -x509 -new -newkey falcon512 \
    -keyout /etc/ssl/private/falcon512_server.key \
    -out /etc/ssl/certs/falcon512_server.crt \
    -nodes \
    -subj "/CN=pq-bridge.yourdomain.com" \
    -days 365 \
    -provider oqsprovider -provider default

sudo chmod 600 /etc/ssl/private/falcon512_server.key

