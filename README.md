Docker部署Nginx+Typecho+Xray简单的一键脚本，可以使用以下命令执行该脚本文件：

```
sudo yum install subversion     #安装svn
https://github.com/weiwuji1/docker-xray-typecho/tree/master/install.sh    #导出项目下的文件夹URL   
https://github.com/weiwuji1/docker-xray-typecho/trunk/install.sh     #将其中tree/master替换成trunk
svn checkout https://github.com/weiwuji1/docker-xray-typecho/trunk/install.sh   #svn checkout下载

sudo chmod +x install.sh
./install.sh
```
脚本通过acme.sh自动申请部署证书，本示例以DNSPod解析域名为例。
需要根据提示填写相关参数。
