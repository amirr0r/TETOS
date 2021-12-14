#!/bin/bash

VM="$1"
IP="$2"
SLOW="$3"

# took this function from https://www.linuxjournal.com/content/validating-ip-address-bash-script
function valid_ip()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

if [ ! -z $VM ] && [ ! -z $IP ]; then
	# 0. Check if it's a valid IP
	if ! $(valid_ip $IP); then echo "Wrong IP? $IP" && exit; fi
	# 1. Check if it's a Linux or a Windows VM 
	ttl=$(ping -c1 $IP | grep -o 'ttl=[0-9][0-9]*' | cut -d'=' -f2)
	if [ ! -z $ttl ] && [ "$ttl" -gt "60" ] && [ "$ttl" -lt "119" ]; then
		echo -e "$VM is probably a \e[1m\e[31mLinux\e[0m machine..."
	elif [ ! -z $ttl ] && [ "$ttl" -gt "119" ] && [ "$ttl" -lt "254" ]; then
		echo -e "$VM is probably a \e[1m\e[34mWindows\e[0m machine..."
	fi	
	# 2. Create directory and go to it
	mkdir $VM
	cd $VM
	printf "# $VM\n\n## Enumeration\n\n### \`nmap\` scan\n\n## Foothold\n\n## Privesc\n\n___\n\n## Useful links\n\n"> README.md
	mkdir services
	mkdir img
	# 3. Start tmux
  	tmux start-server
  	tmux new-session -d -s $VM -n nmap
	echo "export TARGET=$IP" >> ~/.bashrc
	# 3.1 First nmap to get open ports among 1000 common ports
	if [ ! -z "$SLOW" ] && [ "$SLOW" == "slow" ]; then
		tmux send-keys -t $VM:0 "nmap -sS -oN ports.txt $IP -Pn &" C-m
	else
		tmux send-keys -t $VM:0 "nmap -min-rate 5000 --max-retries 1 -sS -oN ports.txt $IP -Pn &" C-m
	fi
	sleep 5
	# For each port ...
	i=1
	USERNAMES="/usr/share/wordlists/seclists/Usernames/top-usernames-shortlist.txt"
    	WEBDIR="/usr/share/wordlists/seclists/Discovery/Web-Content/common.txt"
	for p in $(cat ports.txt | grep -E "^[0-9]" | grep open | cut -d'/' -f1); do
        # Trying FTP Anonymous Login if port 21
        if [ "$p" == "21" ]; then
            tmux new-window -t $VM:$i -n FTP
            tmux send-keys -t $VM:$i "ftp $IP" C-m
            i=$((i+1))
        # SMTP VRFY BASH Script if port 25
        elif [ "$p" == "25" ]; then 
            tmux new-window -t $VM:$i -n SMTP
            tmux send-keys -t $VM:$i "for user in $(cat $USERNAMES); do echo VRFY $user |nc -nv -w 1 $IP $PORT 2>/dev/null |grep ^'250'; done" C-m
            i=$((i+1))
        # DNS if port 53
        elif [ "$p" == "53" ]; then
            tmux new-window -t $VM:$i -n DNS
            tmux send-keys -t $VM:$i "dig axfr @$IP | tee services/53-dns.txt" C-m
            tmux send-keys -t $VM:$i "host $IP | tee services/53-host-DOMAIN.txt" C-m
            tmux send-keys -t $VM:$i "host -t ns $IP | tee services/53-host-NS.txt" C-m
            tmux send-keys -t $VM:$i "host -t mx $IP | tee services/53-host-MX.txt" C-m
            tmux send-keys -t $VM:$i "host -t txt $IP | tee services/53-host-TXT.txt" C-m
            i=$((i+1))
        # FINGER in port 79
        elif [ "$p" == "79" ]; then
            tmux new-window -t $VM:$i -n FINGER
            tmux send-keys -t $VM:$i "/opt/finger-user-enum.pl -U $USERNAMES -t $IP" C-m
            i=$((i+1))
        # HTTP if port 80 
        elif [ "$p" == "80" ]; then
            #tmux new-window -t $VM:$i -n dirb
            #tmux send-keys -t $VM:$i "dirb http://$IP -o services/80-http.txt" C-m
            tmux new-window -t $VM:$i -n HTTP
            #tmux send-keys -t $VM:$i "gobuster dir -u http://$IP -w /usr/share/dirb/wordlists/common.txt -o services/80-http.txt" C-m
            tmux send-keys -t $VM:$i "gobuster dir -u http://$IP -w $WEBDIR -x .txt -o services/80-http.txt;" C-m
            tmux send-keys -t $VM:$i "wait; nikto -h $IP | tee services/80-nikto.txt"
            i=$((i+1))
        # RPC if port 135
        elif [ "$p" == "135" ]; then
            tmux new-window -t $VM:$i -n RPC
            tmux send-keys -t $VM:$i "rpcclient -U '%' $IP | tee services/135-rpc.txt" C-m
            i=$((i+1))
        # LDAP if port 389
        elif [ "$p" == "389" ]; then
            tmux new-window -t $VM:$i -n LDAP
            tmux send-keys -t $VM:$i "ldapsearch -h $IP -x -s base namingcontexts | tee services/ldap.txt" C-m # Test for Anonymous LDAP binds
            i=$((i+1))
        # HTTPS if port 443
        elif [ "$p" == "443" ]; then
            tmux new-window -t $VM:$i -n HTTPS
            tmux send-keys -t $VM:$i "gobuster dir -u https://$IP -w $WEBDIR -x .txt -k -o services/443-https.txt" C-m
            # tmux send-keys -t $VM:$i "wait; nikto -h $IP | tee services/443-nikto.txt" C-m
            i=$((i+1))
        # SMB if port 445
        elif [ "$p" == "445" ] || [ "$p" == "445" ]; then
            tmux new-window -t $VM:$i -n SMB
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
            tmux send-keys -t $VM:$i "showmount -e $IP | tee services/2049-NFS.txt" C-m
            i=$((i+1))
        # MySQL if port 3306
        elif [ "$p" == "3306" ]; then
            tmux new-window -t $VM:$i -n MySQL
            i=$((i+1))
        # RDP if port 3389
        elif [ "$p" == "3389" ]; then
            tmux new-window -t $VM:$i -n RDP
            tmux send-keys -t $VM:$i 'nmap --script "rdp-ntlm-info" -p 3389 -T4 -Pn -oN $VM-rdp-enum.txt $IP;' C-m
            tmux send-keys -t $VM:$i "wait; crowbar -b rdp -s $IP/24 -u $USERNAME -C $WORDLIST -n 1 # '/24' -> NETMASK"
            i=$((i+1))
        # PostgreSQL if port 5432
        elif [ "$p" == "5432" ]; then
            tmux new-window -t $VM:$i -n PostgreSQL
            i=$((i+1))
        fi
    done
	# 3.2 Second nmap with services versions
	tmux send-keys -t $VM:0 "wait; nmap -vvv -sS -sV -oN $VM.txt $IP -Pn &" C-m
	# 3.3 Third nmap - all ports
	tmux send-keys -t $VM:0 "wait; nmap -vvv -sV -sC -p- -oN $VM-full-port-scan.txt $IP -Pn &" C-m
	# 3.4 nmap - UDP
	tmux send-keys -t $VM:0 "wait; nmap -vvv -sU -oN UDP-scan.txt $IP -Pn &" C-m
	# 3.5 Last nmap - vuln
	tmux send-keys -t $VM:0 "wait; nmap -vvv -sS --script vuln -oN vuln-scan.txt $IP -Pn" C-m #-> we don't hit enter because it can be unecessary
	tmux select-window -t $VM:0
	tmux attach-session -t $VM
else
	echo "Usage: bash tetos.sh <VM_name> <IP>"
fi

