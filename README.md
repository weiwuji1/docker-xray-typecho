Docker部署Nginx+Typecho+Xray简单的一键脚本，可以使用以下命令执行该脚本文件：
github 打开某个文件,点击raw或者download打开文件，浏览器查看文件链接,使用wget下载到当前路径

```
wget https://raw.githubusercontent.com/weiwuji1/docker-xray-typecho/main/install.sh
sudo chmod +x install.sh
./install.sh
```
脚本通过acme.sh自动申请部署证书，本示例以DNSPod解析域名为例。
需要根据提示填写相关参数。

### Nginx 前置
支持配置方式`VLESS + TCP + TLS + Nginx + WebSocket`
```
wget -N --no-check-certificate -q -O install-1.sh "https://raw.githubusercontent.com/weiwuji1/docker-xray-typecho/main/install-1.sh" && chmod +x install-1.sh && bash install-1.sh
```
