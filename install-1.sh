#!/bin/bash

# Install docker-ce and docker-compose
#sudo yum install -y yum-utils
#sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
#sudo yum install -y docker-ce docker-ce-cli containerd.io
#sudo systemctl start docker
#sudo systemctl enable docker

#sudo yum install -y epel-release
#sudo yum install -y python3-pip
#sudo pip3 install docker-compose

# 安装依赖关系
sudo apt-get update
sudo apt-get -y install \
    apt-transport-https \
    ca-certificates \
    wget \
    curl \
    gnupg \
    lsb-release

# 添加Docker GPG密钥
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# 配置 Docker 软件源
echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 安装 Docker 引擎
sudo apt-get update
sudo apt-get -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin

# 添加用户到 docker 组
sudo usermod -aG docker $USER


# Creating docker-compose.yml
mkdir -p ./typecho
cat <<EOF >  ./typecho/docker-compose.yml
version: "3"
services: 
    xray:
        image: teddysun/xray
        container_name: xray
        restart: always
        environment: 
            TZ: Asia/Shanghai
        ports: 
            - 10000:10000
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
            CF_Token: 'cf_token'
            CF_Account_ID: 'cf_account_id'
            CF_Zone_ID: 'cf_zonet_id'
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
mkdir -p ./typecho/nginx/conf.d
cat <<EOF > ./typecho/nginx/conf.d/default.conf
server {
    listen      443 ssl;
    listen  [::]:443 ssl;
    server_name  yourdomain.com;
	
	root   /var/www/typecho/;
	index  index.html index.htm index.php;
	
	ssl_certificate      /etc/nginx/ssl/xray.crt;
	ssl_certificate_key  /etc/nginx/ssl/xray.key;
	ssl_protocols TLSv1.1 TLSv1.2;
	ssl_session_timeout  5m;
	ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5:!RC4:!DHE;
	ssl_prefer_server_ciphers  on;
	location  /one {
      	if (\$http_upgrade = "websocket") {
      	  	proxy_pass http://xray:10000;
      	}
      	# 仅当请求为 WebSocket 时才反代到 V2Ray
      	if (\$http_upgrade != "websocket") {
      	 #否则显示正常网页
	      	rewrite ^/(.*)$ /index.php last;
      	}
      	proxy_redirect off;
      	proxy_http_version 1.1;
      	proxy_set_header Upgrade \$http_upgrade;
      	proxy_set_header Connection "upgrade";
      	proxy_set_header Host \$http_host;
      	proxy_set_header X-Real-IP \$remote_addr;
      	proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
	}
  location = /50x.html {
      root   /var/www/typecho/;
  }
}
server {
	 listen 80;
	 server_name yourdomain.com;  
	 rewrite ^(.*)$ https://\$host\$1 permanent;
	 location / {
	    index index.html index.htm index.php;
	  }
}
EOF


# Creating Xray profiles
mkdir -p ./typecho/xray/config
cat <<EOF >  ./typecho/xray/config/config.json
{
    "log": {
        "loglevel": "warning"
    },
    "api": null,
    "routing": {
        "domainStrategy": "IPOnDemand",
        "rules": [
            {
                "type": "field",
                "ip": [
                    "geoip:private",
		    "0.0.0.0/8",
                    "10.0.0.0/8",
                    "100.64.0.0/10",
                    "127.0.0.0/8",
                    "169.254.0.0/16",
                    "172.16.0.0/12",
                    "192.0.0.0/24",
                    "192.0.2.0/24",
                    "192.168.0.0/16",
                    "198.18.0.0/15",
                    "198.51.100.0/24",
                    "203.0.113.0/24",
                    "::1/128",
                    "fc00::/7",
                    "fe80::/10"
                ],
                "outboundTag": "blocked"
            },
	    {
                "type": "field",
                "protocol": [
                    "bittorrent"
                ],
                "outboundTag": "blocked"
            }
        ]
    },
    "policy": {},
    "inbounds": [
        {
            "port": 10000,
            "listen": "0.0.0.0",
            "protocol": "vless",
            "settings": {
                "udp": true,
                "clients": [
                    {
                        "id": "Your-U-U-ID-HERE"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "ws",
                "security": "none",
                "wsSettings": {
                    "path": "/one"
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {
                "domainStrategy": "UseIP"
            },
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "tag": "block"
        }
    ],
    "transport": {},
    "stats": null,
    "reverse": {}
}
EOF

# Modify database credentials in docker-compose.yml
read -p "Enter database username: " DB_USER
read -p "Enter database password: " DB_PASS
read -p "Enter database name: " DB_NAME
read -p "Enter your domain name: " DOMAIN
read -p "Enter your Cloudflare Account ID: " CF_ID
read -p "Enter your Cloudflare Zone ID: " ZONE_ID
read -p "Enter your Cloudflare Token: " CF_TOKEN

sed -i "s/DB_USER/$DB_USER/g" ./typecho/docker-compose.yml
sed -i "s/DB_PASS/$DB_PASS/g" ./typecho/docker-compose.yml
sed -i "s/DB_NAME/$DB_NAME/g" ./typecho/docker-compose.yml
sed -i "s/cf_account_id/$CF_ID/g" ./typecho/docker-compose.yml
sed -i "s/cf_zonet_id/$ZONE_ID/g" ./typecho/docker-compose.yml
sed -i "s/cf_token/$CF_TOKEN/g" ./typecho/docker-compose.yml
sed -i "s/yourdomain.com/$DOMAIN/g" ./typecho/docker-compose.yml

# Modify domain name in nginx config
sed -i "s/yourdomain.com/$DOMAIN/g" ./typecho/nginx/conf.d/default.conf

# Modify UUID and email in Xray config
read -p "Enter Xray UUID: " XRAY_UUID
read -p "Enter email for Xray: " XRAY_EMAIL

sed -i "s/Your-U-U-ID-HERE/$XRAY_UUID/g" ./typecho/xray/config/config.json
sed -i "s/admin@yourdomain.com/$XRAY_EMAIL/g" ./typecho/xray/config/config.json

# Create and start containers
cd ./typecho
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
