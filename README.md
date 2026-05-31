> /usr/local/etc/v2ray/config.json
``` bash
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 10086,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "c8aa717e-7901-4433-be72-5264b38bf5fb",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/pq-tunnel"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
```
> /etc/nginx/nginx.conf

``` bash
user root;
worker_processes auto;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    log_format pq_analytics '$remote_addr - $remote_user [$time_local] '
                            '"$request" $status $body_bytes_sent '
                            '| KEX: $ssl_curves | Cipher: $ssl_cipher';

    access_log /var/log/nginx/pq_access.log pq_analytics;
    error_log /var/log/nginx/pq_error.log warn;

    server {
        listen 0.0.0.0:4433 ssl;
        server_name pq-bridge.yourdomain.com; # CHANGE THIS TO YOUR DOMAIN

        ssl_certificate     /etc/ssl/certs/falcon512_server.crt;
        ssl_certificate_key /etc/ssl/private/falcon512_server.key;

        ssl_protocols TLSv1.3;
        ssl_ecdh_curve p256_mlkem512;

        location /pq-tunnel {
            proxy_redirect off;
            proxy_pass http://127.0.0.1:10086;
            
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $http_host;
            
            proxy_buffering off;
            proxy_read_timeout 300s;
            proxy_send_timeout 300s;
        }
    }
}
```
> ignition
```
sudo systemctl enable v2ray
sudo systemctl restart v2ray
sudo ss -tulpn | grep 10086
sudo /usr/sbin/nginx -t
sudo /usr/sbin/nginx
```
