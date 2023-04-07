#!/bin/bash

# Install docker-ce and docker-compose
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install -y docker-ce docker-ce-cli containerd.io
sudo systemctl start docker
sudo systemctl enable docker

sudo yum install -y epel-release
sudo yum install -y python3-pip
sudo pip3 install docker-compose

# Clone repository
git clone https://github.com/weiwuji1/docker-xray-web.git
cd docker-xray-web

# Modify database credentials in docker-compose.yml
read -p "Enter database username: " DB_USER
read -p "Enter database password: " DB_PASS
read -p "Enter database name: " DB_NAME
read -p "Enter your domain name: " DOMAIN
read -p "Enter your Cloudflare Account ID: " CF_ID
read -p "Enter your Cloudflare Zone ID: " ZONE_ID
read -p "Enter your Cloudflare Token: " CF_TOKEN

sed -i "s/DB_USER/$DB_USER/g" docker-compose-cf.yml
sed -i "s/DB_PASS/$DB_PASS/g" docker-compose-cf.yml
sed -i "s/DB_NAME/$DB_NAME/g" docker-compose-cf.yml
sed -i "s/cf_account_id/$CF_ID/g" docker-compose-cf.yml
sed -i "s/cf_zonet_id/$ZONE_ID/g" docker-compose-cf.yml
sed -i "s/cf_token/$CF_TOKEN/g" docker-compose-cf.yml


# Modify domain name in nginx config
sed -i "s/yourdomain.com/$DOMAIN/g" nginx/conf.d/default.conf

# Modify UUID and email in Xray config
read -p "Enter Xray UUID: " XRAY_UUID
read -p "Enter email for Xray: " XRAY_EMAIL

sed -i "s/Your-U-U-ID-HERE/$XRAY_UUID/g" xray/config/config.json
sed -i "s/admin@yourdomain.com/$XRAY_EMAIL/g" xray/config/config.json

# Create and start containers
sudo docker compose -f docker-compose-cf.yml up -d

# Install certificate
sudo docker exec -i acme acme.sh --register-account -m $XRAY_EMAIL
sudo docker exec -i acme acme.sh --issue --dns dns_dp -d $DOMAIN -d *.$DOMAIN
sudo docker exec -i acme acme.sh --deploy -d $DOMAIN  --deploy-hook docker


# Stop and start containers
sudo docker compose -f docker-compose-cf.yml down
sudo chmod -R 777 nginx
sudo docker compose -f docker-compose-cf.yml up -d

# Typecho 安装后可能需要在程序自动生成的 ./nginx/www/typecho/config.inc.php 中加入一行：define('__TYPECHO_SECURE__',true);
# sed -i -e '$a\define("__TYPECHO_SECURE__", true);' ./nginx/www/typecho/config.inc.php
