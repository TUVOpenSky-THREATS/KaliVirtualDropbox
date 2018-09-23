# KaliVirtualDropbox

**Kali ISO of DOOM** + **autossh & stunnel** + **Kali C2 Server** = **KaliVirtualDropbox**  

Create a Kali virtual dropbox appliance (ISO) to assist with remote Vulnerability Assessments and Penetratino tests that auto installs without any user interaction, and , and calls home to your C2 server using unique shared secrets.  

## Usage

1) Stand up an engagement specific Kali instance/VM
1) Open up 443/tcp to your instance/VM from the outside
1) Clone and execute the script on the C2 host
      ```
      cd /opt
      git clone https://github.com/TUVOpenSky-THREATS/KaliVirtualDropbox
      cd KaliVirtualDropbox
      ./create_ISO_configure_C2.sh
      ```
      Or, if you want to manually specify the C2 IP:
      ```
      ./create_ISO_configure_C2.sh C2_IP_ADDRESS
      ```
      
1) Transfer the ISO to your remote contact
    1) *The ISO will be in /opt/build/images*
    1) *You can use [simple-https-server](https://gist.github.com/dergachev/7028596) or whatever you want to serve the file. If using simple-https server, make sure to host the private keys outside your temporary web root ;)*
1) Your remote contact installs the ISO in a VM, bootable USB, or on hardware
1) On the C2 server, ```ssh root@localhost -p6667``` with the random password provided by the script
1) Configure Nessus or anythign else you want on the box 

## Design Considerations
 
* 1-to-1 mapping between Kali C2 server and the ISO
  * Standing up an engagement specific C2 Kali that will only communicate with one ISO limit exposure. Don't re-use a C2 servers between engagements/clients   
* A low privilege user on the C2 server accepts the ssh tunnel which limits the risk expoxsed if someone compromises or misuses the dropbox
* **autossh over stunel** means The only required open port on the C2 kali is 443/tcp 
