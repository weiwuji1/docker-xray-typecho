#!/bin/bash
DOMAIN=$1
UUID=$2
P=$3
echo "域名："$DOMAIN
echo "uuid："$UUID
echo "路径："$P
echo '回车确定：'
read -s -n 1 key
if [[ $key = "" ]]; then 
    echo '开始执行!'
else
    echo "You pressed '$key'"
    exit 1
fi
function pauseErr(){
    if [ $? -ne 0 ];then
        echo "pause because of failed ; Ctrl + C to exit"
        #沉睡100秒，以便查看异常信息
        sleep 100
        #当调用者使用Ctrl + C打断沉睡之后，直接退出脚本，阻止脚本向下执行
        exit
    fi
}
rm -rf /docker/nginx
rm -rf /docker/xray
echo '安装依赖'
echo "source /etc/profile" >> ~/.bashrc
apt update && apt -y upgrade && apt -y install git curl apt-utils cron wget
pauseErr
echo 'speedtest'
# speedtest
apt -y install python python3 
ln -s /usr/bin/python3 /usr/bin/python
wget https://raw.github.com/sivel/speedtest-cli/master/speedtest.py
chmod a+rx speedtest.py
mv speedtest.py /usr/local/bin/speedtest
chown root:root /usr/local/bin/speedtest

pauseErr
# traceroute 
echo 'traceroute'
apt -y install traceroute

pauseErr
# bbr
echo 'bbr 脚本'
cd ~
wget -O tcp.sh "https://git.io/coolspeeda" && chmod +x tcp.sh 


pauseErr
# docker
echo '安装docker'
apt -y remove docker docker-engine docker.io containerd runc
apt -y update
apt -y install \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

pauseErr
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
pauseErr
echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
pauseErr
apt-get update
apt-get install docker-ce docker-ce-cli containerd.io
systemctl enable --now docker
pauseErr
echo '部署 xray'
# xray
docker rm -f nginx
docker rm -f xray
mkdir -p /docker/xray/
cat <<EOF >  /docker/xray/config.json
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
                "clients": [
                    {
                        "id": "$UUID"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "ws",
                "security": "none",
                "wsSettings": {
                    "path": "/$P"
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

docker run -d -p 10000:10000 -e TZ=Asia/Shanghai --name xray --restart=always -v /docker/xray:/etc/xray teddysun/xray

echo 'xray 已部署完成'

pauseErr

echo '部署 nginx'

# nginx
# 创建映射目录
mkdir -p /docker/nginx/html
mkdir -p /docker/nginx/logs
mkdir -p /docker/nginx/conf

# 获取默认的配置文件
docker run -d -p 80:80 --name nginx nginx:latest
docker cp nginx:/etc/nginx /docker/nginx/conf
cp -r  /docker/nginx/conf/nginx/* /docker/nginx/conf/
rm -rf  /docker/nginx/conf/nginx
docker rm -f nginx

# 部署nginx
docker run -p 80:80 -p 443:443 --link xray:xray -e TZ=Asia/Shanghai --name nginx --restart=always \
-v /docker/nginx/html:/usr/share/nginx/html \
-v /docker/nginx/logs:/var/log/nginx \
-v /docker/nginx/conf:/etc/nginx \
-d nginx:latest

echo 'nginx 已部署完成'

pauseErr

echo '获取伪装网站'
# html
git clone https://github.com/star574/camouflage_html.git
mv camouflage_html/* /docker/nginx/html/
rm -rf camouflage_html

pauseErr

echo '为' ${DOMAIN} '申请证书'
# acme.sh ssl
curl  https://get.acme.sh | sh -s email=my@example.com

pauseErr
source ~/.bashrc

mkdir -p  /etc/nginx/conf/ssl/${DOMAIN}

pauseErr
~/.acme.sh/acme.sh  --issue  -d ${DOMAIN} --webroot  /docker/nginx/html/

mkdir -p  /docker/nginx/conf/ssl/${DOMAIN}/
~/.acme.sh/acme.sh --install-cert -d ${DOMAIN}   \
--key-file       /docker/nginx/conf/ssl/${DOMAIN}/${DOMAIN}.key  \
--fullchain-file /docker/nginx/conf/ssl/${DOMAIN}/fullchain.pem \
--reloadcmd   "docker restart nginx"
pauseErr
echo '证书' ${DOMAIN}_key '部署成功'
touch /docker/nginx/conf/conf.d/${DOMAIN}.conf
cat <<EOF > /docker/nginx/conf/conf.d/${DOMAIN}.conf
server {
    listen      443 ssl;
    listen  [::]:443 ssl;
    server_name  ${DOMAIN};
	
	root   /usr/share/nginx/html;
	index  index.html index.htm;
	
	ssl_certificate      /etc/nginx/ssl/${DOMAIN}/fullchain.pem;
	ssl_certificate_key  /etc/nginx/ssl/${DOMAIN}/${DOMAIN}.key;
	ssl_protocols TLSv1.1 TLSv1.2;
	ssl_session_timeout  5m;
	ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5:!RC4:!DHE;
	ssl_prefer_server_ciphers  on;
	location  /${P} {
      	if (\$http_upgrade = "websocket") {
      	  	proxy_pass http://xray:10000;
      	}
      	# 仅当请求为 WebSocket 时才反代到 V2Ray
      	if (\$http_upgrade != "websocket") {
      	 #否则显示正常网页
	      	rewrite ^/(.*)$ /index.html last;
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
      root   /usr/share/nginx/html;
  }
}
server {
	 listen 80;
	 server_name ${DOMAIN};  
	 rewrite ^(.*)$ https://\$host\$1 permanent;
	 location / {
	    index index.html index.htm;
	  }
}
EOF

pauseErr

echo '同步时间'
systemctl stop ntp.service 
systemctl start ntp.service 
date
rm -rf /etc/localtime
ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
systemctl stop ntp.service 
ntpdate us.pool.ntp.org 
systemctl start ntp.service 
date


mv /docker/nginx/conf/conf.d/default.conf /docker/nginx/conf/conf.d/default.conf.bak

echo '重启docker'
docker restart $(docker ps -qa)
pauseErr
echo '全部应用部署完成！'
