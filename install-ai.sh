#!/bin/bash

# 检查 Docker 是否已经安装
if ! command -v docker &> /dev/null; then
  # 安装 Docker
  echo "正在安装 Docker..."
  sudo apt update
  sudo apt install -y docker.io
fi

# 检查 Docker-compose 是否已经安装
if ! command -v docker-compose &> /dev/null; then
  # 安装 Docker-compose
  echo "正在安装 Docker-compose..."
  sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
fi

# 2. 用 Docker-compose 部署 Xray 和 Web 服务（Nginx + PostgreSQL + Typecho）
echo "正在部署 Xray 和 Web 服务..."
mkdir xray
cd xray

# 3. 生成 Nginx 配置文件
echo "请输入域名"
read -p "域名：" domain

echo "请输入注册证书邮箱："
read -p "域名：" EMAIL

echo "请输入 WebSocket 路径："
read -p "WebSocket 路径：" your_path

cat > nginx.conf << EOF
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

  ssl_certificate /etc/nginx/nginx.crt;
  ssl_certificate_key /etc/nginx/nginx.key;
}
EOF

# 4. 生成 Xray 配置文件
echo "请输入 Xray 的 UUID："
read -p "UUID：" xray_uuid

cat > config.json << EOF
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
            "id": "$xray_uuid",
            "flow": "xtls-rprx-direct",
            "encryption": "none"
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
            "certificateFile": "/etc/xray/config.json/cert.pem",
            "keyFile": "/etc/xray/config.json/key.pem"
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
      - ./config.json:/etc/xray/config.json
      - /root/xray/nginx.crt:/etc/xray/config.json/cert.pem
      - /root/xray/nginx.key:/etc/xray/config.json/key.pem
    ports:
      - 443:443
      - 1080:1080      
      - 443:443/udp

  nginx:
    image: nginx
    restart: always
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf
      - /root/xray/nginx.crt:/etc/nginx/nginx.crt
      - /root/xray/nginx.key:/etc/nginx/nginx.key
      - ./typecho:/var/www/html
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
      - ./typecho:/var/www/html
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

# 6. 通过 acme.sh 自动申请和续签证书（使用 DNSPod 解析域名）
echo "请输入以下参数："
read -p "DNSPodAPI 密钥 ID：" dnspod_api_key_id
read -p "DNSPod API 密钥：" dnspod_api_key

# 安装 acme.sh
echo "正在安装 acme.sh..."
curl https://get.acme.sh | sh

# 设置 DNSPod API 密钥
echo "正在设置 DNSPod API 密钥..."
export DP_Id="$dnspod_api_key_id"
export DP_Key="$dnspod_api_key"

# 使用 acme.sh 申请和安装证书
echo "正在申请和安装证书..."
~/.acme.sh/acme.sh --register-account -m $EMAIL
~/.acme.sh/acme.sh --issue --dns dns_dp -d $domain --keylength ec-256
~/.acme.sh/acme.sh --installcert -d $domain --ecc --fullchain-file /root/xray/nginx.crt --key-file /root/xray/nginx.key

# 启动 Docker-compose 服务
echo "正在启动 Docker-compose 服务..."
sudo docker-compose up -d

# 完成部署
echo "部署完成！"
