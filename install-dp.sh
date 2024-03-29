#!/bin/bash

# Install command line tools 
sudo apt update
sudo apt-get -y install curl wget unzip

# Install docker-ce and docker-compose
sudo curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
sudo apt-get -y install docker-compose-plugin
sudo apt -y autoremove

# Creating docker-compose.yml
sudo mkdir -p ./web
sudo cat <<EOF >  ./web/docker-compose.yml
version: "3"
services: 
    xray:
        image: teddysun/xray
        container_name: xray
        restart: always
        environment: 
            TZ: Asia/Shanghai
        ports: 
            - 20114:20114
            - 20114:20114/udp
        volumes: 
            - ./xray/config:/etc/xray
            - ./xray/logs:/var/log/xray
            - ./cert:/home/root/cert
        depends_on: 
            - acme
        networks: 
            - dockernet

    php:
        image: nat1vus/php-fpm-pgsql
        container_name: php-fpm-pgsql
        restart: always
        environment: 
            TZ: Asia/Shanghai
        volumes: 
            - ./nginx/www:/var/www
        depends_on: 
            - db
        networks: 
            - dockernet

    web:
        image: nginx
        container_name: nginx
        labels:
            - sh.acme.autoload.domain=YourDomain
        restart: always
        environment: 
            TZ: Asia/Shanghai
        ports:
            - 80:80
            - 443:443
        volumes: 
            - ./nginx/conf.d:/etc/nginx/conf.d
            - ./nginx/www:/var/www
            - ./nginx/nginx_logs:/var/log/nginx
            - ./nginx/web_logs:/etc/nginx/logs
            - ./cert:/etc/nginx/ssl
        depends_on: 
            - php
        networks: 
            - dockernet

    db:
        image: postgres:alpine
        container_name: pgsql
        restart: always
        environment: 
            POSTGRES_USER: DB_USER
            POSTGRES_PASSWORD: DB_PASS
            POSTGRES_DB: DB_NAME
            TZ: Asia/Shanghai
        volumes:
            - ./dbdata:/var/lib/postgresql/data
        networks: 
            - dockernet
    acme:
        image: neilpang/acme.sh
        container_name: acme
        restart: always
        environment:
            DP_Id: 'dp_id'
            DP_Key: 'dp_key'
            DEPLOY_DOCKER_CONTAINER_LABEL: 'sh.acme.autoload.domain=YourDomain'
            DEPLOY_DOCKER_CONTAINER_KEY_FILE: '/etc/nginx/ssl/xray.key'
            DEPLOY_DOCKER_CONTAINER_FULLCHAIN_FILE: '/etc/nginx/ssl/xray.crt'
            DEPLOY_DOCKER_CONTAINER_RELOAD_CMD: 'service nginx force-reload'
            TZ: Asia/Shanghai
        volumes:
            - /var/run/docker.sock:/var/run/docker.sock:ro
            - ./acme/acme.sh:/acme.sh
            - ./cert:/etc/nginx/ssl
        command: daemon
        networks: 
            - dockernet

networks: 
    dockernet:
EOF

# Creating nginx profiles
sudo mkdir -p ./web/nginx/conf.d
sudo cat <<EOF > ./web/nginx/conf.d/default.conf
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    ssl_certificate       /etc/nginx/ssl/xray.crt;
    ssl_certificate_key   /etc/nginx/ssl/xray.key;
    ssl_protocols         TLSv1.2 TLSv1.3;
    ssl_ecdh_curve        X25519:P-256:P-384:P-521;
    server_name           YourDomain;
    index index.html index.htm index.php;
    root  /var/www;
    error_page 400 = /400.html;

    ssl_stapling on;
    ssl_stapling_verify on;
    add_header Strict-Transport-Security "max-age=63072000" always;

    location / {
        index index.php;
        try_files \$uri \$uri/ /index.php?q=\$uri&\$args;
    }

    location ~ \.php$ {
        fastcgi_pass php-fpm-pgsql:9000;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location /700028709c/ {
        proxy_redirect off;
        proxy_pass http://xray:20114;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;       
    }
}

server {
    listen 80;
    listen [::]:80;
    server_name YourDomain;
    return 301 https://\$http_host\$request_uri;
}

EOF


# Creating Xray profiles
sudo mkdir -p ./web/xray/config
sudo cat <<EOF >  ./web/xray/config/config.json
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 20114,
      "listen": "0.0.0.0",
      "tag": "VLESS-in",
      "protocol": "VLESS",
      "settings": {
        "udp": true,
	"clients": [
          {
            "id": "UUID",
            "alterId": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/700028709c/"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "dns": {
    "servers": [
      "https+local://1.1.1.1/dns-query",
      "1.1.1.1",
      "1.0.0.1",
      "8.8.8.8",
      "8.8.4.4",
      "localhost"
    ]
  },
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "inboundTag": [
          "VLESS-in"
        ],
        "outboundTag": "direct"
      }
    ]
  }
}
EOF

# Modify database credentials in docker-compose.yml
read -p "输入数据库用户名: " DB_USER
read -p "输入数据库密码: " DB_PASS
read -p "输入数据库名: " DB_NAME
read -p "输入域名: " DOMAIN
read -p "输入用于注册Acme和Xray的Email: " XRAY_EMAIL
read -p "输入DNSpod ID: " DP_ID
read -p "输入DNSpod Key: " DP_KEY

sed -i "s/DB_USER/$DB_USER/g" ./web/docker-compose.yml
sed -i "s/DB_PASS/$DB_PASS/g" ./web/docker-compose.yml
sed -i "s/DB_NAME/$DB_NAME/g" ./web/docker-compose.yml
sed -i "s/dp_key/$DP_KEY/g" ./web/docker-compose.yml
sed -i "s/dp_id/$DP_ID/g" ./web/docker-compose.yml
sed -i "s/YourDomain/$DOMAIN/g" ./web/docker-compose.yml

# Modify domain name in nginx config
sed -i "s/YourDomain/$DOMAIN/g" ./web/nginx/conf.d/default.conf

# Modify UUID and email in Xray config
read -p "输入Xray的UUID: " XRAY_UUID
#read -p "输入Xray的WS伪装路径: " XRAY_PATH

sed -i "s/UUID/$XRAY_UUID/g" ./web/xray/config/config.json
#sed -i "s/10db92a7f3//$XRAY_PATH/g" ./web/xray/config/config.json

# Create and start containers
cd ./web
sudo docker compose up -d

# Install certificate
#sudo docker exec -i acme acme.sh --upgrade -b dev
#sudo docker exec -i acme acme.sh --register-account -m $XRAY_EMAIL
#sudo docker exec -i acme acme.sh --issue --dns dns_dp -d $DOMAIN -d *.$DOMAIN
#sudo docker exec -i acme acme.sh --deploy -d $DOMAIN  --deploy-hook docker
#echo “56 * * * * docker exec acme.sh --cron > /dev/null” >> /var/spool/cron/root

#临时解决nginx证书问题
#cp -r /root/web/cert/. /root/web/nginx/cert

# Stop and start containers
#sudo docker compose down
sudo chmod -R 777 nginx
#sudo docker compose up -d

wget --no-check-certificate --content-disposition https://github.com/typecho/typecho/releases/download/v1.2.1/typecho.zip -P ./nginx/www
cd ./nginx/www
sudo unzip -q typecho.zip
sudo chmod -R 777 ./usr/uploads
sudo rm -f ./typecho.zip

# Typecho 安装后可能需要在程序自动生成的 ./nginx/www/typecho/config.inc.php 中加入一行：define('__TYPECHO_SECURE__',true);
# sed -i -e '$a\define("__TYPECHO_SECURE__", true);' ./nginx/www/typecho/config.inc.php
