#!/usr/bin/env bash
set -euo pipefail

echo ">>> Updating System and Build Chains..."
sudo apt update 
sudo apt install -y build-essential cmake ninja-build git wget libpcre3-dev zlib1g-dev libunwind-dev python3-pytest

BUILD_DIR="/tmp/oqs_build"
mkdir -p $BUILD_DIR && cd $BUILD_DIR

echo ">>> Building Stable OpenSSL 3.3.0..."
if [ ! -d "openssl" ]; then
    git clone --depth 1 -b openssl-3.3 https://github.com/openssl/openssl.git
fi
if [ ! -f "/opt/openssl/bin/openssl" ]; then
    cd openssl
    ./config --prefix=/opt/openssl --openssldir=/opt/openssl/ssl
    make -j2
    sudo make install 
    cd ..
fi

echo ">>> Building liboqs..."
if [ ! -d "liboqs" ]; then 
    git clone --depth 1 -b main https://github.com/open-quantum-safe/liboqs.git
fi
if [ ! -d "/opt/liboqs/include" ]; then
    cd liboqs
    mkdir -p build && cd build 
    cmake -GNinja -DOQS_USE_OPENSSL=ON -DOPENSSL_ROOT_DIR=/opt/openssl -DCMAKE_INSTALL_PREFIX=/opt/liboqs ..
    ninja && sudo ninja install 
    cd ../..
    echo -e "/opt/liboqs/lib\n/opt/liboqs/lib64" | sudo tee /etc/ld.so.conf.d/liboqs.conf
    sudo ldconfig
fi

echo ">>> Building oqsprovider..."
if [ ! -f "/opt/openssl/lib64/ossl-modules/oqsprovider.so" ]; then
    if [ ! -d "oqs-provider" ]; then
        git clone --depth 1 -b main https://github.com/open-quantum-safe/oqs-provider.git
    fi
    cd oqs-provider
    rm -rf build && mkdir build && cd build
    cmake -DOPENSSL_ROOT_DIR=/opt/openssl -DCMAKE_BUILD_TYPE=Release -Dliboqs_DIR=/opt/liboqs ..
    make
    sudo mkdir -p /opt/openssl/lib64/ossl-modules/
    sudo cp lib/oqsprovider.so /opt/openssl/lib64/ossl-modules/
    cd ../..
    echo -e "/opt/openssl/lib\n/opt/openssl/lib64" | sudo tee /etc/ld.so.conf.d/openssl.conf
    sudo ldconfig
fi

echo ">>> Compiling Nginx..."
ngver="1.24.0"
if [ ! -f "nginx-${ngver}.tar.gz" ]; then
    wget https://nginx.org/download/nginx-${ngver}.tar.gz
    tar -zxvf nginx-${ngver}.tar.gz
fi
if [ ! -f "/usr/sbin/nginx" ]; then
    cd nginx-${ngver}
    make clean || true
    ./configure \
        --prefix=/etc/nginx \
        --sbin-path=/usr/sbin/nginx \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --pid-path=/var/run/nginx.pid \
        --lock-path=/var/run/nginx.lock \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-stream \
        --with-stream_ssl_module \
        --with-cc-opt="-I/opt/openssl/include -Wno-error" \
        --with-ld-opt="-L/opt/openssl/lib64 -L/opt/openssl/lib -Wl,-rpath,/opt/openssl/lib64 -Wl,-rpath,/opt/openssl/lib"
    make -j2
    sudo make install
    cd ..
fi

echo ">>> Injecting Pristine OpenSSL Config..."
sudo cp /tmp/oqs_build/openssl/apps/openssl.cnf /opt/openssl/ssl/openssl.cnf
sudo sed -i '/^openssl_conf/d' /opt/openssl/ssl/openssl.cnf
sudo sed -i '1i openssl_conf = openssl_init\n\n[openssl_init]\nproviders = provider_sect\n\n[provider_sect]\ndefault = default_sect\noqsprovider = oqsprovider_sect\n\n[default_sect]\nactivate = 1\n\n[oqsprovider_sect]\nactivate = 1\nmodule = /opt/openssl/lib64/ossl-modules/oqsprovider.so\n' /opt/openssl/ssl/openssl.cnf

sudo ldconfig
echo ">>> Core Server Engine Ready."


curl -O https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh
sudo bash install-release.sh

echo " v2ray installed "

