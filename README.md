# KaliVirtualDropbox

**Kali ISO of DOOM** + **autossh & stunnel** + **Kali C2 Server** = **KaliVirtualDropbox**  

Create a Kali virtual dropbox appliance (ISO) for use during remote Vulnerability Assessments and Penetration tests that auto installs without any user interaction, and calls home to your C2 server using unique shared secrets.  

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
1) On the C2 host, with the randomly generated password provided by the script, or the ssh key located in /root/~.ssh/dropbox.key
    ```
    ssh root@localhost -p9999
    sudo ssh root@localhost -p9999 -i /root/.ssh/dropbox.key
    ```
1) Configure Nessus or anything else you want on the box 

