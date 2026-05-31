set -e

GCP_IP="34.66.173.193"
CERT_CN="pq-bridge.yourdomain.com"
BUILD_DIR="/tmp/oqs_build"
OPENSSL_PATH="/opt/openssl"
V2RAY_CONFIG="/usr/local/etc/v2ray/config.json"
NGINX_CONFIG="/etc/nginx/nginx.conf"

echo ">>> [1/6] Initializing System & Dependencies..."
sudo apt-get update -y
sudo apt-get install -y build-essential cmake ninja-build git wget libpcre3-dev zlib1g-dev libunwind-dev python3-pytest curl

mkdir -p "$BUILD_DIR"

echo ">>> [2/6] Building Stable OpenSSL 3.3.0 with OQS support..."
cd "$BUILD_DIR"
if [ ! -d "openssl" ]; then
    git clone --depth 1 --branch openssl-3.3.0 https://github.com/openssl/openssl.git
fi
if [ ! -d "liboqs" ]; then
    git clone --depth 1 --branch main https://github.com/open-quantum-safe/liboqs.git
fi
if [ ! -d "oqsprovider" ]; then
    git clone --depth 1 --branch main https://github.com/open-quantum-safe/oqsprovider.git
fi

cd "$BUILD_DIR/liboqs"
mkdir -p build && cd build
cmake -G Ninja -DCMAKE_INSTALL_PREFIX="$OPENSSL_PATH" ..
ninja
sudo ninja install

cd "$BUILD_DIR/openssl"
if [ ! -f "config.status" ]; then
    ./config --prefix="$OPENSSL_PATH" --openssldir="$OPENSSL_PATH" shared zlib
fi
make -j$(nproc)
sudo make install_sw

cd "$BUILD_DIR/oqsprovider"
mkdir -p build && cd build
cmake -G Ninja -DCMAKE_PREFIX_PATH="$OPENSSL_PATH" -DCMAKE_INSTALL_PREFIX="$OPENSSL_PATH" ..
ninja
sudo ninja install

echo ">>> [3/6] Compiling Post-Quantum Nginx Wrapper..."
cd "$BUILD_DIR"
if [ ! -f "nginx-1.24.0.tar.gz" ]; then
    wget --no-check-certificate https://nginx.org/download/nginx-1.24.0.tar.gz
fi
if [ ! -d "nginx-1.24.0" ]; then
    tar -zxvf nginx-1.24.0.tar.gz
fi

cd nginx-1.24.0
./configure \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --conf-path=/etc/nginx/nginx.conf \
    --pid-path=/var/run/nginx.pid \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --with-openssl="$BUILD_DIR/openssl" \
    --with-http_ssl_module \
    --with-http_v2_module

sed -i "s|./config|./config --prefix=$OPENSSL_PATH --openssldir=$OPENSSL_PATH|g" objs/Makefile

make -j$(nproc)
sudo make install

echo ">>> [4/6] Setting Up Certificates & Nginx Routing Layer..."
sudo mkdir -p /etc/nginx/certs
sudo mkdir -p /var/log/nginx

if [ -f "$HOME/pq-workspace/certs/falcon512_server.crt" ]; then
    sudo cp "$HOME/pq-workspace/certs/falcon512_server.crt" /etc/nginx/certs/falcon512_server.crt
elif [ -f "$HOME/pq-v2ray-bridge/falcon512_server.crt" ]; then
    sudo cp "$HOME/pq-v2ray-bridge/falcon512_server.crt" /etc/nginx/certs/falcon512_server.crt
fi
sudo chmod 644 /etc/nginx/certs/falcon512_server.crt

sudo tee "$NGINX_CONFIG" > /dev/null << EOF
user root;
worker_processes auto;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    log_format client_pq_log '\$time_local | Tunnel Status: \$status | Sent: \$body_bytes_sent B';
    access_log /var/log/nginx/client_access.log client_pq_log;
    error_log /var/log/nginx/client_error.log warn;

    server {
        listen 127.0.0.1:8443;
        server_name localhost;

        location /pq-tunnel {
            proxy_redirect off;
            proxy_pass https://$GCP_IP:4433;
            
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$http_host;
            
            proxy_ssl_protocols TLSv1.3;
            proxy_ssl_conf_command Groups p256_mlkem512;
            
            proxy_ssl_trusted_certificate /etc/nginx/certs/falcon512_server.crt;
            proxy_ssl_verify on;
            proxy_ssl_server_name on;
            proxy_ssl_name $CERT_CN;
            proxy_ssl_verify_depth 2;

            proxy_buffering off;
            proxy_read_timeout 300s;
            proxy_send_timeout 300s;
        }
    }
}
EOF

echo ">>> [5/6] Installing & Configuring V2Ray Client Core..."
cd "$BUILD_DIR"
curl -O https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh
sudo bash install-release.sh

sudo mkdir -p /usr/local/etc/v2ray
sudo tee "$V2RAY_CONFIG" > /dev/null << EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 10808,
      "listen": "127.0.0.1",
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "127.0.0.1",
            "port": 8443,
            "users": [
              {
                "id": "c8aa717e-7901-4433-be72-5264b38bf5fb",
                "encryption": "none",
                "level": 0
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/pq-tunnel"
        }
      }
    }
  ]
}
EOF

echo ">>> [6/6] Launching Services & Verifying Bindings..."
sudo killall nginx 2>/dev/null || true
sudo systemctl stop v2ray 2>/dev/null || true
sudo service v2ray stop 2>/dev/null || true

sudo /usr/sbin/nginx -t

sudo /usr/sbin/nginx
sudo systemctl start v2ray 2>/dev/null || sudo service v2ray start

echo "=============================================================================="
echo " >>> POST-QUANTUM CLIENT DISPATCHED SUCCESSFULLY <<<"
echo " SOCKS5 Proxy Listening on: 127.0.0.1:10808"
echo " Quantum TLS Tunnel Forwarder on: 127.0.0.1:8443"
echo "=============================================================================="
sudo ss -tulpn | grep -E '8443|10808'
