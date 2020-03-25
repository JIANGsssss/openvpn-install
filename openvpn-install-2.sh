#!/bin/bash
####################################################
#                                                  #
# This is a OpenVPN installation for CentOS 7      #
# Version: 1.3.0 20160729                          #
# Author: Jinquan Deng                             #
# WEB: http://www.jiobxn.com                       #
#                                                  #
####################################################

#检测是否是root用户
if [[ $(id -u) != "0" ]]; then
    printf "\e[42m\e[31mError: You must be root to run this install script.\e[0m\n"
    exit 1
fi

#检测是否是CentOS 7或者RHEL 7
if [[ $(grep "release 7." /etc/redhat-release 2>/dev/null | wc -l) -eq 0 ]]; then
    printf "\e[42m\e[31mError: Your OS is NOT CentOS 7 or RHEL 7.\e[0m\n"
    printf "\e[42m\e[31mThis install script is ONLY for CentOS 7 and RHEL 7.\e[0m\n"
    exit 1
fi
clear

printf "
####################################################
#                                                  #
# This is a OpenVPN installation for CentOS 7      #
# Version: 1.3.0 20160729                          #
# Author: Jinquan Deng                             #
# WEB: http://www.jiobxn.com                       #
#                                                  #
####################################################
"

#获取服务器IP
IP=$(ip route |grep $(ip route |grep default |awk '{print $5}') |grep src |awk '{print $9}' |head -1)

read  -p "Server IP: [ $IP ] "  serverip
if [ -z $serverip ]; then
    serverip=$IP
    if [ -z $serverip ]; then
        echo "none ip. BYE!"
        exit 1
    fi
fi

#获取网卡接口名称
DEV=$(ip route |grep $serverip |awk '{print $3}' |head -1)

read  -p "Network Interface: [ $DEV ] " eth
if [ -z $eth ]; then
    eth=$DEV
    if [ -z $eth ]; then
        echo "None Interface. BYE!"
        exit 0
    fi
fi

#设置VPN拨号后分配的IP段
read  -p "Default IP-Range: [ 10.8.0 ] "  iprange
if [ -z $iprange ]; then
    iprange=10.8.0
fi

#设置监听端口
read  -p "Default Port: [ 11194 ] "  port
if [ -z $port ]; then
    port=11194
fi

#设置服务协议
read  -p "TCP or UDP server？: [ udp ] "  tcp_udp
if [ -z $tcp_udp ]; then
    tcp_udp=udp
fi

#设置接口模式
read  -p "TAP or TUN interface？: [ tun ] "  tap_tun
if [ -z $tap_tun ]; then
    tap_tun=tun
fi

#设置网关
read  -p "Default GATEWAY is VPN？: [ Y ] "  gateway_vpn
if [ -z $gateway_vpn ]; then
    gateway_vpn=Y
    gatewayvpn=yes
fi


#打印配置参数
echo "   "
clear

echo -e "IP-Range => $iprange.0/24
ServerIP => $serverip
Port => $port
Protocol => $tcp_udp
Interface => $tap_tun
Gateway is VPN => $gatewayvpn
"

read -p "Continue?(y/n): [y]" next
if [ -z $next ]; then
        echo "---------Start install the configuration!---------"
else

    if [ "$next" != "y" ]; then
        echo "---------BYE!---------"
        exit 0
    else
        echo "---------Start write the configuration!---------"
    fi
fi


#清理安装包
systemctl stop openvpn@server.service
rpm -e openvpn easy-rsa

#安装依赖的组件
yum clean all
yum -y update
yum install -y openvpn easy-rsa

if [ $? -ne 0 ]; then
    echo "Installation FAILED!"
    exit 1
fi

#创建配置文件
\cp -R /usr/share/easy-rsa/* /etc/openvpn/server/
\cp -R /usr/share/easy-rsa/* /etc/openvpn/client/
\cp /usr/share/doc/openvpn-*/sample/sample-config-files/{server.conf,client.conf} /etc/openvpn/

#创建CA证书、密钥和Diffie-Hellman参数文件
cd /etc/openvpn/server/3
./easyrsa init-pki
echo | ./easyrsa gen-req server nopass

cd /etc/openvpn/client/3
./easyrsa init-pki
echo | ./easyrsa build-ca nopass
echo | ./easyrsa import-req /etc/openvpn/server/3/pki/reqs/server.req server
echo yes | ./easyrsa sign-req server server
./easyrsa gen-dh

echo | ./easyrsa gen-req client nopass
echo yes | ./easyrsa sign-req client client

#复制证书到相应的目录
\cp /etc/openvpn/client/3/pki/issued/* /etc/openvpn/
\cp /etc/openvpn/server/3/pki/private/* /etc/openvpn/
\cp /etc/openvpn/client/3/pki/private/* /etc/openvpn/
\cp /etc/openvpn/client/3/pki/ca.crt /etc/openvpn/
\cp /etc/openvpn/client/3/pki/dh.pem /etc/openvpn/dh2048.pem
cd ~

#编辑server.conf配置文件
sed -i "s/port 1194/port $port/g" /etc/openvpn/server.conf
sed -i "s/proto udp/proto $tcp_udp/g" /etc/openvpn/server.conf
# "dev tun" will create a routed IP tunnel
# "dev tap" will create a ethernet tunnel,IOS doesn't support
sed -i "s/^dev tun/dev $tap_tun/g" /etc/openvpn/server.conf
sed -i "s/server 10.8.0.0 255.255.255.0/server $iprange.0 255.255.255.0/g" /etc/openvpn/server.conf
sed -i "s/;client-to-client/client-to-client/g" /etc/openvpn/server.conf
sed -i "s/;duplicate-cn/duplicate-cn/g" /etc/openvpn/server.conf
sed -i "s/;max-clients 100/max-clients 253/g" /etc/openvpn/server.conf
sed -i 's/explicit-exit-notify/;explicit-exit-notify/' /etc/openvpn/server.conf

if [ "$gateway_vpn" = "Y" ]; then
    sed -i 's/;push "redirect-gateway def1 bypass-dhcp"/push "redirect-gateway def1 bypass-dhcp"/g' /etc/openvpn/server.conf
else
    sed -i 's/;push "dhcp-option DNS 208.67.222.222"/push "dhcp-option DNS 8.8.8.8"\npush "route 8.8.8.8 255.255.255.255"/g' /etc/openvpn/server.conf
    sed -i 's/;push "dhcp-option DNS 208.67.220.220"/push "dhcp-option DNS 8.8.4.4"\npush "route 8.8.4.4 255.255.255.255"/g' /etc/openvpn/server.conf
fi

#编辑client.conf配置文件
sed -i "s/^dev tun/dev $tap_tun/g" /etc/openvpn/client.conf
sed -i "s/proto udp/proto $tcp_udp/g" /etc/openvpn/client.conf
sed -i "s/remote my-server-1 1194/remote $serverip $port/g" /etc/openvpn/client.conf
\cp /etc/openvpn/client.conf /etc/openvpn/client.ovpn


#开启网络转发功能
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

#防火墙配置
systemctl restart iptables.service
iptables -I INPUT -p $tcp_udp -m state --state NEW -m $tcp_udp --dport $port -j ACCEPT
iptables -t nat -A POSTROUTING -s $iprange.0/24 -o $eth -j MASQUERADE
iptables -D FORWARD -j REJECT --reject-with icmp-host-prohibited
iptables-save > /etc/sysconfig/iptables

#SELinux设置
audit2allow -a -M mypol
semodule -i mypol.pp

#允许开机启动
systemctl enable openvpn@server.service
systemctl start openvpn@server.service
systemctl status openvpn@server.service

printf "
####################################################
#                                                  #
# This is a OpenVPN installation for CentOS 7      #
# Version: 1.3.0 20160729                          #
# Author: Jinquan Deng                             #
# WEB: http://www.jiobxn.com                       #
#                                                  #
####################################################
if there are no [FAILED] above, then you can

IOS Client:
Into the App Store is installed OpenVPN.
The following files using itunes imported into OpenVPN:
/etc/openvpn/ca.crt
/etc/openvpn/client.crt
/etc/openvpn/client.key
/etc/openvpn/client.ovpn

Linux Client:
yum -y install openvpn
scp /etc/openvpn/{ca.crt,client.crt,client.key,client.conf} your-openvpn-client:/etc/openvpn
systemctl start openvpn@client.service
" |tee openvpn.log
