#!/bin/bash

sleep 30

sudo apt-get update -y
sudo apt install wireguard -y

#Variables Declared
HowMany=$1
#What is the starting Static IP of Clients
StartIPAddr=$2
#Public IP
serverIP=$3
# Change User
SrvUser=$4
#Domanin Controllers DNS
# DNS=10.200.200.1
DNS=$5
DNS2=$6
#Allowed IPs
AllowedIPs=$7


# Setup Folders & Server Keys

mkdir /home/${SrvUser}/wg
mkdir /home/${SrvUser}/wg/keys
mkdir /home/${SrvUser}/wg/clients
mkdir /home/${SrvUser}/wg/backup/
sudo umask 077


sudo wg genkey | tee /home/${SrvUser}/wg/keys/server_private_key | wg pubkey > /home/${SrvUser}/wg/keys/server_public_key

echo "
[Interface]
Address = 10.200.200.1/22
SaveConfig = true
ListenPort = 443
PrivateKey=$(cat /home/${SrvUser}/wg/keys/server_private_key)" | sudo tee /etc/wireguard/wg0.conf

sudo sysctl -w net.ipv4.ip_forward=1

## IP Forwarding
sed -i -e 's/#net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
# sed -i -e 's/#net.ipv6.conf.all.forwarding.*/net.ipv6.conf.all.forwarding=1/g' /etc/sysctl.conf
# sudo sysctl -p /etc/sysctl.conf
sysctl -p

sudo iptables -A FORWARD -i wg0 -j ACCEPT

sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

sudo iptables -t nat -A POSTROUTING -s 10.200.200.0/24 -o eth0 -j MASQUERADE

echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections

sudo apt install iptables-persistent -y
sudo systemctl enable netfilter-persistent
sudo netfilter-persistent save
 
sudo wg-quick up wg0 &&log
sudo systemctl enable wg-quick@wg0


#Config Loop
for i in $(seq $HowMany); do
# Test Loop and Show current Static IP ending
    echo $StartIPAddr

    wg genkey | tee /home/$SrvUser/wg/keys/${StartIPAddr}_private_key | wg pubkey > /home/$SrvUser/wg/keys/${StartIPAddr}_public_key
    
    wg set wg0 peer $(cat /home/${SrvUser}/wg/keys/${StartIPAddr}_public_key) allowed-ips 10.200.200.${StartIPAddr}/32 | sudo bash -

    echo "[Interface]
        Address = 10.200.200.${StartIPAddr}/32
        PrivateKey = $(cat "/home/${SrvUser}/wg/keys/${StartIPAddr}_private_key")
        DNS = ${DNS}, ${DNS2}
        MTU = 1380
        [Peer]
        PublicKey = $(cat "/home/${SrvUser}/wg/keys/server_public_key")
        Endpoint = ${serverIP}:443
        AllowedIPs = ${AllowedIPs}
        PersistentKeepalive = 21" > /home/$SrvUser/wg/clients/${StartIPAddr}.conf
    
    
    StartIPAddr=$((StartIPAddr+1))

           
    done
    
# Add backup service -> Downloads backup script to wg/backup and creates a crontab at midnight on the first day of every month to run the backup script. 
wget https://raw.githubusercontent.com/Ortus-Ireland/wgConfig/main/wg-backup.sh -P /home/${SrvUser}/wg/backup/
sudo sh /home/${SrvUser}/wg/backup/wg-backup.sh $SrvUser

crontab -l > /home/${SrvUser}/wg/backup/wgcron
#echo new cron into cron file
echo "0 0 1 * * /home/${SrvUser}/wg/backup/wg-backup.sh" >> /home/${SrvUser}/wg/backup/wgcron
#install new cron file
crontab -u ${SrvUser} /home/${SrvUser}/wg/backup/wgcron
rm /home/${SrvUser}/wg/backup/wgcron    
    
sudo chown -R $SrvUser /home/$SrvUser/wg

wg-quick down wg0
sleep 2
wg-quick up wg0
