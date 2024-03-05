#!/bin/bash

# 1. 安装 Docker 和 Docker Compose
echo "正在安装 Docker 和 Docker Compose..."
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# 2. 部署 Xray 和 Web 服务（Nginx + PostgreSQL + Typecho）
echo "正在部署 Xray 和 Web 服务..."
mkdir -p ./web/nginx
mkdir -p ./web/xray
mkdir -p ./web/cert
mkdir -p ./web/typecho

echo "请输入域名："
read -p "域名： " domain

echo "请输入注册证书邮箱："
read -p "邮箱： " email

echo "请输入 WebSocket 路径："
read -p "WebSocket 路径： " ws_path

echo "请输入 Xray UUID:"
read -p "UUID: " xray_uuid

echo "请输入 PostgreSQL 密码："
read -sp "PostgreSQL 密码： " postgres_password
echo

# 生成 Nginx 配置文件
cat > ./web/nginx/nginx.conf << EOF
server {
    listen 80;
    server_name $domain;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl;
    server_name $domain;

    ssl_certificate /etc/nginx/cert/nginx.crt;
    ssl_certificate_key /etc/nginx/cert/nginx.key;

    location / {
        proxy_pass http://typecho:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
    }

    location $ws_path {
        proxy_pass http://xray:15243;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
    }
}
EOF

# 生成 Xray 配置文件
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
      "port": 15243,
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
          "path": "$ws_path"
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
EOF

# 生成 Docker Compose 配置文件
cat > docker-compose.yml << EOF
version: '3'
services:
  xray:
    image: teddysun/xray
    restart: always
    volumes:
      - ./web/xray:/etc/xray
    ports:
      - 15243:15243
      - 15243:15243/udp
      - 1080:1080
    networks:
      - app-network

  nginx:
    image: nginx
    restart: always
    volumes:
      - ./web/nginx:/etc/nginx/conf.d
      - ./web/cert:/etc/nginx/cert
      - ./web/typecho:/var/www/html
    ports:
      - 80:80
      - 443:443
    networks:
      - app-network

  typecho:
    image: 80x86/typecho
    restart: always
    environment:
      - DB_TYPE=pgsql
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_NAME=typecho
      - DB_USER=typecho
      - DB_PASSWD="$postgres_password"
    volumes:
      - ./web/typecho:/usr/share/nginx/html
    depends_on:
      - postgres
    networks:
      - app-network

  postgres:
    image: postgres
    restart: always
    environment:
      - POSTGRES_PASSWORD="$postgres_password"
      - POSTGRES_DB=typecho
      - POSTGRES_USER=typecho
    volumes:
      - postgres-data:/var/lib/postgresql/data
    networks:
      - app-network

volumes:
  postgres-data:

networks:
  app-network:
    driver: bridge
EOF

# 3. 自动申请和续签证书
echo "请输入 Cloudflare API Key:"
read -p "Cloudflare API Key: " cf_api_key

# 安装 acme.sh
echo "正在安装 acme.sh..."
sudo apt-get install -y socat
curl https://get.acme.sh | sh

# 设置 Cloudflare API Key 和 Email
export CF_Key="$cf_api_key"
export CF_Email="$email"

# 使用 acme.sh 申请和安装证书
echo "正在申请和安装证书..."
sudo ~/.acme.sh/acme.sh --register-account -m $email
sudo ~/.acme.sh/acme.sh --issue --dns dns_cf -d $domain -d *.$domain --keylength ec-256 --force
sudo ~/.acme.sh/acme.sh --installcert -d $domain --ecc --fullchain-file ./web/cert/nginx.crt --key-file ./web/cert/nginx.key

# 4. 启动 Docker Compose 服务
echo "正在启动 Docker Compose 服务..."
sudo docker compose up -d

# 5. 完成部署
echo "部署完成！"
