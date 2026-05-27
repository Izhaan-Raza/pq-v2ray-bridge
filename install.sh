#!/bin/bash

mkdir -p ./certs

if [[ "$1" == "server" ]]; then
    echo "init server mode [ubuntu only!!]"

    echo "generating Falcon-512 Keypair..."
    docker run --rm -v "$(pwd)/certs:/keys" \
        openquantumsafe/curl \
        openssl req -x509 -new -newkey falcon512 \
        -keyout /keys/falcon512.key \
        -out /keys/falcon512.crt \
        -nodes \
        -subj "/CN=PQ-Bridge" \
        -days 365 2>/dev/null

    sleep 0.7
    echo "key generated !!"

    if [[ "$2" == "tail" ]]; then
        TS_IP=$(tailscale ip -4)
    fi

    if [[ "$2" == "host" ]]; then
        TS_IP=$(hostname -I | awk '{print $1}')
    fi

    sleep 0.5
    echo "using ip $TS_IP"

    echo "Starting bootstrap server on port 8080.."
    cd ./certs
    python3 -m http.server 8080 --bind $TS_IP > /dev/null 2>&1 &
    HTTP_PID=$!
    cd ..

    echo "Leave this terminal open, switch to client and run:"
    echo "  ./install.sh client $TS_IP"

    read -p "Press [ENTER] to kill the http server once the client successfully connects."

    kill $HTTP_PID
    echo "Server terminated. Port 8080 locked down"

    sleep 0.3
    echo "starting nginx container......"
    
    docker run -d --name oqs-proxy \
        --restart unless-stopped \
        -p 4433:4433 \
        -v "$(pwd)/certs/falcon512.crt:/opt/nginx/certs/falcon512.crt:ro" \
        -v "$(pwd)/certs/falcon512.key:/opt/nginx/certs/falcon512.key:ro" \
        -v "$(pwd)/src/nginx-server.conf:/opt/nginx/nginx-conf/nginx.conf:ro" \
        openquantumsafe/nginx

    echo "starting v2ray core......"
    sudo cp "$(pwd)/src/v2ray-server.json" /usr/local/etc/v2ray/config.json
    sudo systemctl restart v2ray

    echo "[SUCCESS] Server Bridge is fully operational."
    exit 0

elif [[ "$1" == "client" ]]; then
    SERVER_IP=$2

    if [[ -z "$SERVER_IP" ]]; then
        echo "[!] FATAL: You must provide the Server's IP."
        echo "Usage: ./install.sh client <SERVER_IP>"
        exit 1
    fi

    echo "init client mode"
    echo "Reaching out to Ephemeral Server at http://$SERVER_IP:8080..."
    
    curl -s -f -o ./certs/falcon512.crt http://$SERVER_IP:8080/falcon512.crt
    
    if [[ $? -ne 0 ]]; then
        echo "[!] FATAL: Failed to fetch the public key. Is the server script waiting?"
        exit 1
    fi

    echo "Public key secured! You can press ENTER on the server now."
    sleep 1

    echo "Configuring NGINX route to $SERVER_IP..."
    sed "s/SERVER_IP_PLACEHOLDER/$SERVER_IP/g" "$(pwd)/src/nginx-client.conf" > "$(pwd)/src/nginx-client-active.conf"

    echo "starting nginx container......"
    docker run -d --name oqs-client \
        --restart unless-stopped \
        -p 4433:4433 \
        -v "$(pwd)/certs/falcon512.crt:/opt/nginx/certs/falcon512.crt:ro" \
        -v "$(pwd)/src/nginx-client-active.conf:/opt/nginx/nginx-conf/nginx.conf:ro" \
        openquantumsafe/nginx

    echo "starting v2ray core......"
    pkill v2ray || true
    cd ./src
    nohup ./v2ray run -config v2ray-client.json > ../v2ray.log 2>&1 &
    cd ..

    echo "[SUCCESS] Client bridge established on local port 1080."
    exit 0

else
    echo "Usage:"
    echo "  Server: ./install.sh server [tail|host]"
    echo "  Client: ./install.sh client <SERVER_IP>"
    exit 1
fi
