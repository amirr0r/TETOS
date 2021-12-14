#!/bin/bash

# TETOS POP (Tiny Enumeration Tmux Organizer Script - Post Open Ports)
# * This script requires a text file with a list of open ports following this format:
#   <PORT NUMBER> open
# * Note: If you saved nmap's output (-oN), this will be automatic, you just have to pass the text file as the second argument. 
# I usually use it once I identified open ports of a machine that I have to reach via proxychains.

IP=$1
SCAN=$2 # nmap scan output text file
VM=$3
PROXYCHAINS=$4 # "127.0.0.1:1080" for example

if [ ! -z $SCAN ]  && [ ! -z $IP ]; then
    if [ -z $VM ]; then
        VM=$(echo $IP | tr '.' '_')
    fi
    mkdir -p $VM/services
    cd $VM
    SCAN="../$SCAN"
    cp $SCAN .
    
    USERNAMES="/usr/share/wordlists/seclists/Usernames/top-usernames-shortlist.txt"
    WEBDIR="/usr/share/wordlists/seclists/Discovery/Web-Content/common.txt"
    # Start tmux
    tmux start-server
    tmux new-session -d -s $VM -n nmap
    tmux send-keys -t $VM:0 "cat $SCAN" C-m
    # echo "export TARGET=$IP" >> ~/.bashrc
    # For each port ...
    i=1
    for p in $(cat $SCAN | grep -E "^[0-9]" | grep open | cut -d'/' -f1); do
        # Trying FTO Anonymous Login if port 21
        if [ "$p" == "21" ]; then
            tmux new-window -t $VM:$i -n FTP
            tmux send-keys -t $VM:$i "ftp $IP" C-m
            i=$((i+1))
        # SMTP VRFY BASH Script if port 25
        elif [ "$p" == "25" ]; then 
            tmux new-window -t $VM:$i -n SMTP
            tmux send-keys -t $VM:$i 'for user in $(cat $USERNAMES); do echo VRFY $user |nc -nv -w 1 $IP $PORT 2>/dev/null |grep ^"250"; done' #C-m
            i=$((i+1))
        # DNS if port 53
        elif [ "$p" == "53" ]; then
            tmux new-window -t $VM:$i -n DNS
            if [ ! -z $PROXYCHAINS ]; then
                tmux send-keys -t $VM:$i 'proxychains '
            fi
            tmux send-keys -t $VM:$i "dig axfr @$IP | tee services/53-dns.txt;" C-m
            tmux send-keys -t $VM:$i "host $IP | tee services/53-host-DOMAIN.txt;"
            tmux send-keys -t $VM:$i "host -t ns $IP | tee services/53-host-NS.txt;"
            tmux send-keys -t $VM:$i "host -t mx $IP | tee services/53-host-MX.txt;"
            tmux send-keys -t $VM:$i "host -t txt $IP | tee services/53-host-TXT.txt;"
            i=$((i+1))
        # FINGER in port 79
        elif [ "$p" == "79" ]; then
            tmux new-window -t $VM:$i -n FINGER
            tmux send-keys -t $VM:$i "/opt/finger-user-enum.pl -U $USERNAMES -t $IP" C-m
            i=$((i+1))
        # HTTP if port 80 
        elif [ "$p" == "80" ]; then
            tmux new-window -t $VM:$i -n HTTP
            if [ ! -z $PROXYCHAINS ]; then
                tmux send-keys -t $VM:$i 'HTTP_PROXY="socks5://$PROXYCHAINS/" '
            fi
            tmux send-keys -t $VM:$i "gobuster dir -u http://$IP -w $WEBDIR -x .txt -o services/80-http.txt" C-m
            i=$((i+1))
        # RPC if port 135
        elif [ "$p" == "135" ]; then
            tmux new-window -t $VM:$i -n RPC
            if [ ! -z $PROXYCHAINS ]; then
                tmux send-keys -t $VM:$i 'proxychains '
            fi
            tmux send-keys -t $VM:$i "rpcclient -U '%' $IP | tee services/135-rpc.txt" C-m
            i=$((i+1))
        # LDAP if port 389
        elif [ "$p" == "389" ]; then
            tmux new-window -t $VM:$i -n LDAP
            if [ ! -z $PROXYCHAINS ]; then
                tmux send-keys -t $VM:$i 'proxychains '
            fi
            tmux send-keys -t $VM:$i "ldapsearch -h $IP -x -s base namingcontexts | tee services/ldap.txt" C-m # Test for Anonymous LDAP binds
            i=$((i+1))
        # HTTPS if port 443
        elif [ "$p" == "443" ]; then
            tmux new-window -t $VM:$i -n HTTPS
            if [ ! -z $PROXYCHAINS ]; then
                tmux send-keys -t $VM:$i 'HTTPS_PROXY="socks5://$PROXYCHAINS/" '
            fi
            tmux send-keys -t $VM:$i "gobuster dir -u https://$IP -w $WEBDIR -x .txt -k -o services/443-https.txt" C-m
            # tmux send-keys -t $VM:$i "wait; nikto -h $IP | tee services/443-nikto.txt" C-m
            i=$((i+1))
        # SMB if port 445
        elif [ "$p" == "445" ] || [ "$p" == "445" ]; then
            tmux new-window -t $VM:$i -n SMB
            if [ ! -z $PROXYCHAINS ]; then
                tmux send-keys -t $VM:$i 'proxychains '
            fi
            tmux send-keys -t $VM:$i "smbclient -L //$IP -U '%' | tee services/445-smbclient.txt" C-m
            tmux send-keys -t $VM:$i "wait; crackmapexec smb $IP --shares;"
            tmux send-keys -t $VM:$i "wait; smbmap -H $IP -R | tee services/445-smbmap.txt"
            i=$((i+1))
            tmux new-window -t $VM:$i -n enum4linux
            tmux send-keys -t $VM:$i "enum4linux -a $IP | tee linux-enum.txt" C-m # enumerate SMB shares on both Windows and Linux systems
            i=$((i+1))
        # Oracle TNS Listener if port 1521
        elif [ "$p" == "1521" ]; then
            tmux new-window -t $VM:$i -n Oracle
            tmux send-keys -t $VM:$i "git clone https://github.com/quentinhardy/odat.git" C-m
            i=$((i+1))
        # NFS if port 2049
        elif [ "$p" == "2049" ]; then
            tmux new-window -t $VM:$i -n NFS
            if [ ! -z $PROXYCHAINS ]; then
                tmux send-keys -t $VM:$i 'proxychains '
            fi
            tmux send-keys -t $VM:$i "showmount -e $IP | tee services/2049-NFS.txt" C-m
            i=$((i+1))
        # MySQL if port 3306
        elif [ "$p" == "3306" ]; then
            tmux new-window -t $VM:$i -n MySQL
            i=$((i+1))
        # RDP if port 3389
        elif [ "$p" == "3389" ]; then
            tmux new-window -t $VM:$i -n RDP
            if [ ! -z $PROXYCHAINS ]; then
                tmux send-keys -t $VM:$i 'proxychains '
            fi
            tmux send-keys -t $VM:$i "nmap --script "rdp-ntlm-info" -p 3389 -T4 -Pn -oN $VM-rdp-enum.txt $IP;" C-m
            tmux send-keys -t $VM:$i "wait; crowbar -b rdp -s $IP/24 -u $USERNAME -C $WORDLIST -n 1 # '/24' -> NETMASK"
            i=$((i+1))
        # PostgreSQL if port 5432
        elif [ "$p" == "5432" ]; then
            tmux new-window -t $VM:$i -n PostgreSQL
            i=$((i+1))
        fi
    done
    tmux select-window -t $VM:0
    tmux attach-session -t $VM
else
    echo "Usage: bash tetos_pop.sh <IP> <PORTS_SCAN_OUTPUT> [VM_name] [PROXYCHAINS]"
fi
