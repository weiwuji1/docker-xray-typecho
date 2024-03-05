#!/bin/bash

# 检查 Docker 是否已经安装
if ! command -v docker &> /dev/null; then
  # 安装 Docker
  echo "正在安装 Docker..."
  sudo apt update
  sudo apt-get -y install curl wget unzip
  sudo curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
fi

# 检查 Docker Compose 是否已经安装
if ! command -v docker compose &> /dev/null; then
  # 安装 Docker Compose
  echo "正在安装 Docker Compose..."
  sudo apt-get -y install docker-compose-plugin
fi

# 2. 用 Docker compose 部署 Xray 和 Web 服务（Nginx + PostgreSQL + Typecho）
echo "正在部署 Xray 和 Web 服务..."
# 创建配置文件目录
mkdir -p ./web/nginx
mkdir -p ./web/xray
mkdir -p ./web/cert
mkdir -p ./web/typecho

# 3. 生成 Nginx 配置文件
echo "请输入域名"
read -p "域名：" domain

echo "请输入注册证书邮箱："
read -p "邮箱：" EMAIL

echo "请输入 WebSocket 路径："
read -p "WebSocket 路径：" your_path

cat > ./web/nginx/default.conf << EOF
server {
  listen 80;
  server_name $domain;

  location / {
    proxy_pass http://typecho:8080;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
  }

  location $your_path {
    proxy_pass http://xray:443;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$http_host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
  }

  ssl_certificate /etc/nginx/cert/nginx.crt;
  ssl_certificate_key /etc/nginx/cert/nginx.key;
}
EOF

# 4. 生成 Xray 配置文件
echo "请输入 Xray 的 UUID："
read -p "UUID：" xray_uuid

cat > ./web/xray/config.json << EOF
{
  "inbounds": [
    {
      "port": 1080,
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    },
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$xray_uuid"
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": 1080,
            "xver": 1
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "$your_path"
        }
      },
      "tlsSettings": {
        "certificates": [
          {
            "certificateFile": "/home/root/cert/nginx.crt",
            "keyFile": "/home/root/cert/nginx.key"
          }
        ]
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
EOF

# 5. 生成 Docker-compose 配置文件
echo "请输入 PostgreSQL 密码："
read -sp "PostgreSQL 密码：" postgres_password

cat > docker-compose.yml << EOF
version: '3'
services:
  xray:
    image: teddysun/xray
    restart: always
    volumes:
      - /root/web/xray:/etc/xray
      - /root/web/cert:/home/root/cert
    ports:
      - 443:443
      - 1080:1080      
      - 443:443/udp

  nginx:
    image: nginx
    restart: always
    volumes:
      - /root/web/nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
      - /root/web/cert:/etc/nginx/cert
      - /root/web/typecho:/var/www/html
    ports:
      - 80:80

  typecho:
    image: 80x86/typecho
    restart: always
    environment:
      - DB_TYPE=pgsql
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_NAME=typecho
      - DB_USER=typecho
      - DB_PASSWD=$postgres_password
    volumes:
      - /root/web/typecho:/usr/share/nginx/html
    depends_on:
      - postgres
    ports:
      - 8080:80

  postgres:
    image: postgres
    restart: always
    environment:
      - POSTGRES_PASSWORD=$postgres_password
      - POSTGRES_DB=typecho
      - POSTGRES_USER=typecho
    volumes:
      - postgres-data:/var/lib/postgresql/data

volumes:
  postgres-data:
  typecho:
EOF

# 6. 通过 acme.sh 自动申请和续签证书（使用 Cloudflare 解析域名）
echo "请输入以下参数："
read -p "CloudFlare API 密钥：" CF_api_key

# 安装 acme.sh
echo "正在安装 acme.sh..."
sudo apt install socat
curl https://get.acme.sh | sh

# 设置 Cloudflare API 密钥
echo "正在设置 CloudFlare API 密钥..."
export CF_Key="$CF_api_key"
export CF_Email="$EMAIL"

# 使用 acme.sh 申请和安装证书
echo "正在申请和安装证书..."
~/.acme.sh/acme.sh --register-account -m $EMAIL
~/.acme.sh/acme.sh --issue --dns dns_cf -d $domain -d *.$domain --keylength ec-256 --force
~/.acme.sh/acme.sh --installcert -d $domain --ecc --fullchain-file /root/web/cert/nginx.crt --key-file /root/web/cert/nginx.key
# 加--force强制更新--reloadcmd docker exec nginx nginx -s force-reload

# 启动 Docker compose 服务
echo "正在启动 Docker compose 服务..."
sudo docker compose up -d

# 完成部署
sudo apt -y autoremove
echo "部署完成！"
