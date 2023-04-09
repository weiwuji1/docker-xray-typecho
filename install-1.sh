#!/bin/bash

# Install docker-ce and docker-compose
sudo curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
sudo apt-get -y install docker-compose-plugin

# Creating docker-compose.yml
mkdir -p ./web
cat <<EOF >  ./web/docker-compose.yml
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
        image: nginx:alpine
        container_name: nginx
        labels:
            - sh.acme.autoload.domain=yourdomain.com
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
            CF_Key: 'cf_key'
            CF_Email: 'cf_email'
            DEPLOY_DOCKER_CONTAINER_LABEL: 'sh.acme.autoload.domain=yourdomain.com'
            DEPLOY_DOCKER_CONTAINER_KEY_FILE: '/etc/nginx/ssl/xray.key'
            DEPLOY_DOCKER_CONTAINER_FULLCHAIN_FILE: '/etc/nginx/ssl/xray.crt'
            DEPLOY_DOCKER_CONTAINER_RELOAD_CMD: 'service nginx force-reload'
            TZ: Asia/Shanghai
        volumes:
            - /var/run/docker.sock:/var/run/docker.sock:ro
            - ./acme/acme.sh:/acme.sh
            - ./nginx/cert:/etc/nginx/ssl
        command: daemon
        networks: 
            - dockernet

networks: 
    dockernet:
EOF

# Creating nginx profiles
mkdir -p ./web/nginx/conf.d
cat <<EOF > ./web/nginx/conf.d/default.conf
    server {
	listen 443 ssl http2;
	listen [::]:443 ssl http2;
        ssl_certificate       /etc/nginx/ssl/xray.crt;
        ssl_certificate_key   /etc/nginx/ssl/xray.key;
        ssl_protocols         TLSv1.2 TLSv1.3;
        ssl_ecdh_curve        X25519:P-256:P-384:P-521;
        server_name           yourdomain.com;
        index index.html index.htm index.php;
        root  /var/www/typecho;
        error_page 400 = /400.html;

        ssl_stapling on;
        ssl_stapling_verify on;
        add_header Strict-Transport-Security "max-age=63072000" always;

        if (!-e $request_filename) {
            rewrite ^(.*)$ /index.php$1 last;
        }
	location ~ .*\.php(\/.*)*$ {
            include fastcgi.conf;
            fastcgi_split_path_info ^(.+?.php)(/.*)$;
            fastcgi_pass  php-fpm-pgsql:9000;
        }

	location /10db92a7f3/
        {
            proxy_redirect off;
	proxy_pass http://xray:20114;
            proxy_http_version 1.1;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $http_host;
        }
}
    server {
        listen 80;
        listen [::]:80;
        server_name yourdomain.com;
        return 301 https://$http_host$request_uri;
    }
EOF


# Creating Xray profiles
mkdir -p ./web/xray/config
cat <<EOF >  ./web/xray/config/config.json
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 20114,
      "listen": "127.0.0.1",
      "tag": "VLESS-in",
      "protocol": "VLESS",
      "settings": {
        "udp": true,
	"clients": [
          {
            "id": "Your-U-U-ID-HERE",
            "alterId": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/10db92a7f3/"
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
read -p "Enter database username: " DB_USER
read -p "Enter database password: " DB_PASS
read -p "Enter database name: " DB_NAME
read -p "Enter your domain name: " DOMAIN
read -p "Enter your Email for Cloudflare Acme Xray: " XRAY_EMAIL
read -p "Enter your Cloudflare API key: " CF_KEY

sed -i "s/DB_USER/$DB_USER/g" ./web/docker-compose.yml
sed -i "s/DB_PASS/$DB_PASS/g" ./web/docker-compose.yml
sed -i "s/DB_NAME/$DB_NAME/g" ./web/docker-compose.yml
sed -i "s/cf_email/$XRAY_EMAIL/g" ./web/docker-compose.yml
sed -i "s/cf_key/$CF_KEY/g" ./web/docker-compose.yml
sed -i "s/yourdomain.com/$DOMAIN/g" ./web/docker-compose.yml

# Modify domain name in nginx config
sed -i "s/yourdomain.com/$DOMAIN/g" ./web/nginx/conf.d/default.conf

# Modify UUID and email in Xray config
read -p "Enter Xray UUID: " XRAY_UUID

sed -i "s/Your-U-U-ID-HERE/$XRAY_UUID/g" ./web/xray/config/config.json
sed -i "s/admin@yourdomain.com/$XRAY_EMAIL/g" ./web/xray/config/config.json

# Create and start containers
cd ./web
sudo docker compose up -d

# Install certificate
sudo docker exec -i acme acme.sh --register-account -m $XRAY_EMAIL
sudo docker exec -i acme acme.sh --issue --dns dns_cf -d $DOMAIN -d *.$DOMAIN
sudo docker exec -i acme acme.sh --deploy -d $DOMAIN  --deploy-hook docker


# Stop and start containers
sudo docker compose down
sudo chmod -R 777 nginx
sudo docker compose up -d

wget --no-check-certificate --content-disposition https://github.com/typecho/typecho/releases/download/v1.2.1-rc/typecho.zip -P ./nginx/www
cd ./nginx/www
sudo apt-get install unzip
unzip *.zip

# Typecho 安装后可能需要在程序自动生成的 ./nginx/www/typecho/config.inc.php 中加入一行：define('__TYPECHO_SECURE__',true);
# sed -i -e '$a\define("__TYPECHO_SECURE__", true);' ./nginx/www/typecho/config.inc.php
