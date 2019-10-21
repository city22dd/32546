#!/bin/bash


function blue(){
    echo -e "\033[34m\033[01m $1 \033[0m"
}
function green(){
    echo -e "\033[32m\033[01m $1 \033[0m"
}
function red(){
    echo -e "\033[31m\033[01m $1 \033[0m"
}
function yellow(){
    echo -e "\033[33m\033[01m $1 \033[0m"
}


#安装nginx
install_nginx(){
    green "====装完bbr加速后可能会重启一次，若重启，请再次运行此脚本完成剩余安装===="
#删除防火墙
    apt update -y
    apt upgrade -y
    yum update -y
    ufw disable
    apt-get remove iptables -y
    chkconfig iptables off
    systemctl disable firewalld
    yum remove firewalld -y
    rm -rf /usr/local/aegis
    rm -rf /usr/local/cloudmonitor
    rm -rf /usr/sbin/aliyun-service
    pkill wrapper.syslog.id
    pkill wrapper
    pkill CmsGoAgent
    pkill aliyun-service
    service aegis stop
    rm -rf /usr/bin/networkd-dispatcher
    pkill networkd
    rm -rf /etc/init.d/aegis
#安装bbr
    wget --no-check-certificate https://github.com/teddysun/across/raw/master/bbr.sh
    chmod 777 bbr.sh
    ./bbr.sh
    yum install -y libtool perl-core zlib-devel gcc wget pcre* unzip lrzsz wget
    apt install -y libtool zlib1g zlib1g-dev gcc wget unzip pcregrep pcredz pcre2-utils perl libpcre3 libpcre3-dev lrzsz wget
    wget https://www.openssl.org/source/openssl-1.1.1a.tar.gz
    tar zxf openssl-1.1.1a.tar.gz
    
    mkdir /etc/nginx
    mkdir /etc/nginx/ssl
    mkdir /etc/nginx/conf.d
    wget https://nginx.org/download/nginx-1.17.4.tar.gz
    tar zxf nginx-1.17.4.tar.gz
    cd nginx-1.17.4
    ./configure --prefix=/etc/nginx --with-openssl=../openssl-1.1.1a --with-openssl-opt='enable-tls1_3' --with-http_v2_module --with-http_ssl_module --with-http_gzip_static_module --with-http_stub_status_module --with-http_sub_module --with-stream --with-stream_ssl_module
    make && make install
##清除垃圾
    cd ..
rm -rf nginx-1.17.4
rm -rf bbr.sh
rm -rf nginx-1.17.4.tar.gz
rm -rf openssl-1.1.1a.tar.gz
rm -rf openssl-1.1.1a
rm -rf install_bbr.log
    
    green "====输入解析到此VPS的域名（建议复制到剪贴板粘贴进来，一旦填错，无法修改）===="
    read domain
    
#获取证书
cat > /etc/nginx/conf/nginx.conf <<-EOF
user  root;
worker_processes  1;
error_log  /etc/nginx/logs/error.log warn;
pid        /etc/nginx/logs/nginx.pid;
events {
    worker_connections  1024;
}
http {
    include       /etc/nginx/conf/mime.types;
    default_type  application/octet-stream;
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log  /etc/nginx/logs/access.log  main;
    sendfile        on;
    #tcp_nopush     on;
    keepalive_timeout  120;
    client_max_body_size 20m;
    #gzip  on;
    include /etc/nginx/conf.d/*.conf;
}
EOF

cat > /etc/nginx/conf.d/default.conf<<-EOF
server {
    listen       80;
    server_name  $domain;
    root /etc/nginx/html;
    index index.php index.html index.htm;
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /etc/nginx/html;
    }
}
EOF

    /etc/nginx/sbin/nginx

    curl https://get.acme.sh | sh
    ~/.acme.sh/acme.sh  --issue  -d $domain  --webroot /etc/nginx/html/ -k ec-256
    ~/.acme.sh/acme.sh  --installcert  -d  $domain   \
        --key-file   /etc/nginx/ssl/$domain.key \
        --fullchain-file /etc/nginx/ssl/fullchain.cer \
        --reloadcmd  "/etc/nginx/sbin/nginx -s reload" --ecc
	
#获取证书结束
}
#安装v2ray
install_v2ray(){
    
    bash <(curl -L -s https://install.direct/go.sh)
    cd /etc/v2ray/
    path=$(cat /dev/urandom | head -1 | md5sum | head -c 4)  ##从系统信息获取随机值作为path
##配置v2ray文件
    sed -i 0,/}],/s/}],/}],rsa/ config.json
    sed -i s#}],rsa#,\"streamSettings\":{\"network\"# config.json
    sed -i s#\"network\"#\"network\":\"ws\",\"wsSettings\":{\"pa# config.json
    sed -i s#gs\":{\"pa#gs\":{\"path\":\"/$path\"}}}],# config.json
##配置完成
##获取端口和id
    port=`grep port config.json`
    port=${port##*' '}
    port=${port%%,*}
    v2id=`grep id config.json`
    v2id=${v2id#*:}
##配置nginx
cat > /etc/nginx/conf/nginx.conf <<-EOF
worker_processes  1;
events {
    worker_connections  1024;
}
http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;
    include /etc/nginx/conf.d/*.conf;
}
EOF
cat > /etc/nginx/conf.d/default.conf<<-EOF
server { 
    listen 80;
    server_name  $domain;
    rewrite ^(.*) https://\$server_name permanent;
}
server {
  listen  443 ssl http2;
  ssl_certificate       /etc/nginx/ssl/fullchain.cer;
  ssl_certificate_key   /etc/nginx/ssl/$domain.key;
  ssl_protocols         TLSv1.3;
  ssl_ciphers           TLS13-AES-128-GCM-SHA256:TLS13-AES256-GCM-SHA384:TLS13-CHACHA20-POLY1305-SHA256:TLS13-AES128-CCM-SHA256:TLS13-AES128-CCM-8-SHA256;
  root /etc/nginx/html;
  index index.html;
  server_name $domain;
        location /$path {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:$port;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        }
}
EOF
    cd /etc/nginx/html
    rm -f /etc/nginx/html/*
    wget https://github.com/atrandys/v2ray-ws-tls/raw/master/web.zip  ##下载网站模板，用于伪装
    unzip web.zip
    /etc/nginx/sbin/nginx -s stop
    /etc/nginx/sbin/nginx
    service v2ray restart
    
    #增加自启动脚本（已废除）
#cat > /etc/rc.d/init.d/autov2ray<<-EOF
#!/bin/sh
#chkconfig: 2345 80 90
#description:autov2ray
#/etc/nginx/sbin/nginx
#EOF

#    chmod +x /etc/rc.d/init.d/autov2ray
#    chkconfig --add autov2ray
#    chkconfig autov2ray on

clear
green
green "安装已经完成"
green 
green "===========配置参数============"
green "地址：${domain}"
green "端口：443"
green "id：${v2id}"
green "额外id：0-64(任填其一，建议4)"
green "加密方式：aes-128-gcm"
green "传输协议：ws"
green "路径：${path}"
green "底层传输：tls"
green "allowinsecure:flase"
green "注意事项：为了加强不同系统兼容性，自动运行脚本已废除，如重新启动服务器，请执行/etc/nginx/sbin/nginx"
green "此魔改脚本仅供交流学习使用，请勿使用此脚本行违法之事。网络非法外之地，行非法之事，必将接受法律制裁。"
green "魔改作者：华南理工大学某大一学生"
green "2019.10 "
green 
}

remove_v2ray(){

    /etc/nginx/sbin/nginx -s stop
    systemctl stop v2ray.service
    systemctl disable v2ray.service
    
    rm -rf /usr/bin/v2ray /etc/v2ray
    rm -rf /etc/v2ray
    rm -rf /etc/nginx
    
    green "nginx、v2ray已删除"
    
}

start_menu(){
    clear
    green " ===================================="
    green " 介绍：一键安装v2ray+ws+tls1.3魔改版        "
    green " 原作者：atrandys                      "
    green " 原作者网站：www.atrandys.com              "
    green " 原作者Youtube：atrandys                   "
    green " 原脚本下载地址：https://github.com/atrandys/v2ray-ws-tls                      "
    green " 魔改内容："
    green " 1.增加bbr加速。"
    green " 2.更新nginx到1.17.4。"
    green " 3.增加删除阿里云盾的命令。"
    green " 4.改变申请证书为ecc证书，密钥长度为256，更安全和快速。"
    green " 5.删除赘余代码"
    green " 6.尽量避免了对官方配置文件的修改"
    green " ===================================="
    echo
    green " 1. 安装v2ray+ws+tls1.3"
    green " 2. 升级v2ray"
    red " 3. 卸载v2ray"
    yellow " 0. 退出脚本"
    blue "建议不要使用小键盘"
    echo
    read -p "请输入数字:" num
    case "$num" in
    1)
    install_nginx
    install_v2ray
    ;;
    2)
    bash <(curl -L -s https://install.direct/go.sh)
    ;;
    3)
    remove_v2ray 
    ;;
    0)
    exit 1
    ;;
    *)
    clear
    red "请输入正确数字"
    sleep 2s
    start_menu
    ;;
    esac
}

start_menu
