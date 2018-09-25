# KaliVirtualDropbox

**Kali ISO of DOOM** + **autossh & stunnel** + **Kali C2 Server** = **KaliVirtualDropbox**  

Create a Kali virtual dropbox appliance (ISO) for use during remote Vulnerability Assessments and Penetration tests that auto installs without any user interaction, and calls home to your C2 server using unique shared secrets.  

## Notes
The most common use case is to run this script on an engagement specific Kali instance (the C2 host). However, the script can be run on another host. In that case, this script creates another bash script (c2_setup.sh) that you need to transfer to and execute on your C2 host.   




## Usage

1) Stand up an engagement specific Kali instance/VM (C2 host)
1) Open up 443/tcp to your C2 host from the outside
1) Clone and execute the script on the C2 host
      ```
      cd /opt
      sudo git clone https://github.com/TUVOpenSky-THREATS/KaliVirtualDropbox
      cd KaliVirtualDropbox
      sudo ./create_ISO_configure_C2.sh
      ```
      This script will pull the public IP for the server and use that. If you want to manually specify the C2 IP, provide the IP as the first parameter:
      ```
      sudo ./create_ISO_configure_C2.sh C2_IP_ADDRESS
      ```
      
1) Transfer the ISO to your remote contact
    1) *The ISO will be in /opt/build/images*
    1) *You can use [simple-https-server](https://gist.github.com/dergachev/7028596) or whatever you want to serve the file. If using simple-https server, make sure to host the private keys outside your temporary web root ;)*
1) Your remote contact installs the ISO in a VM, bootable USB, or on hardware
1) On the C2 host, SSH to your dropbox with the randomly generated password provided by the script OR the ssh key located in /root/~.ssh/dropbox.key
    ```
    ssh root@localhost -p9999 <then enter password> or, 
    sudo ssh root@localhost -p9999 -i /root/.ssh/dropbox.key
    ```
1) Configure Nessus or anything else you want on the box 


## What the script does to your Kali C2 host
* Stunnel Configuration
    1) Creates a new ssl key for stunnel
    1) Creates a config file for stunnel    
    1) Starts stunnel (listens 443/tcp and redirects to 22/tcp locally)
    
* SSH/User Configuration 
    1) Creates a user [autossh]  
    1) Creates ssh keypair for the autossh user
    1) Adds public key to authorized_keys for autossh  
    1) Private key is copied to ISO and is used by the Dropbox to connect to the C2
    1) While the dropbox can establish a tunnel with the C2, it can not execute commands on C2
      
* Dropbox Custom ISO Creation
    1) Grabs public IP of C2 host
    1) Creates a random password for Dropbox
    1) Installs ISO creation toolkit (live-build, etc.)
    1) Downloads live-build config from kali.org
    1) Copies unique, newly created ssh keypair to ISO
    1) Creates remote callback script on ISO that calls back to public IP of C2
    1) Adds script to cron on ISO
    1) Configures ISO to auto install
    1) Configures sshd config on ISO
    1) Enables services on ISO
    1) Asks you if you want to copy a Nessus binary to ISO (optional)
    1) Builds ISO    