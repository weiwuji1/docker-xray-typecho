Docker部署Nginx+Typecho+Xray简单的一键脚本：
（获取文件下载路径：github 打开某个文件,点击raw或者download打开文件，浏览器查看文件链接,使用wget下载到当前路径）

```
wget -N --no-check-certificate -q -O install.sh "https://raw.githubusercontent.com/weiwuji1/docker-xray-typecho/main/install.sh" && chmod +x install.sh && bash install.sh
```
脚本通过acme.sh自动申请部署证书，本示例以DNSPod解析域名为例。
需要根据提示填写相关参数。

### Nginx 前置
最近不知是不是用chatGPT比较多的原因，443端口老是被封，借鉴wulabing大大的Nginx前置脚本自己简单制作了daocker+typecho的一键脚本，用`VLESS+TCP+TLS+Nginx+WebSocket`协议试验一段时间
```
wget -N --no-check-certificate -q -O install-1.sh "https://raw.githubusercontent.com/weiwuji1/docker-xray-typecho/main/install-1.sh" && chmod +x install-1.sh && bash install-1.sh
```
