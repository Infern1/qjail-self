#!/bin/sh
         
function=$1
jailname=$2
nicname=$3
firewall=$4
           
           
start () {  
                    
jid=`jls -j ${jailname} jid` 
               
if [ "${jid}" -gt "100" ]; then
  echo " "         
  echo "WARNING: The JID value is greater then 100."
  echo "This may indicate many cycles of starting/stopping vnet jails"
  echo "which results in lost memory pages. To recover the lost memory,"
  echo "shutdown the host and reboot. This will zero out the JID counter"
  echo "and make all the memory available again."
  echo " "       
fi               
              
if [ "${jid}" -gt "250" ]; then
  echo " "             
  echo "ERROR: No more vnet jail epair ip addresses can be created."
  echo "You MUST shutdown the host and reboot before vnet jails are"
  echo "startable again."
  echo " "             
  exit 2              
fi                  
                  
# Check the hosts network for existing bridge.
# If no bridge yet then create the bridge.
# Add real interface device name to one side of bridge.
#             
bridge=`ifconfig | grep -m 1 bridge | cut -f 1 -d :`
if [ -z ${bridge} ]; then
  ifconfig bridge0 create > /dev/null 2> /dev/null
  ifconfig bridge0 addm ${nicname}
  ifconfig bridge0 up
  # vnet jails will not work unless ip forwarding is enabled.
  sysctl net.inet.ip.forwarding=1 > /dev/null 2> /dev/null
fi           
            
# Do this logic for all vnet jails.
# Assign alias IP number to bridge using jid to make it unique per vnet jail.
# The alias IP number is the vnet jails default route ip address.
# Create epair assigning "a" to bridge and "b" to the vnet jail
#             
ifconfig bridge0 alias 10.${jid}.0.1
ifconfig epair${jid} create > /dev/null 2> /dev/null
ifconfig bridge0 addm epair${jid}a
ifconfig epair${jid}a up
ifconfig epair${jid}b vnet ${jid}
             
# Assign ip address to epair "b" inside of the vnet jail.
#            
jexec ${jailname} ifconfig epair${jid}b 10.${jid}.0.2
jexec ${jailname} route add default 10.${jid}.0.1 > /dev/null 2> /dev/null
jexec ${jailname} ifconfig lo0 127.0.0.1
                    
                    
if [ ${firewall} = "none" ]; then
  # If no firewall was selected in config -v
  # Start services inside of jail needed for network.
  # Note: using service command because it's not nojail keyword aware.
  #                 
  jexec ${jailname} service netif start > /dev/null 2> /dev/null
  jexec ${jailname} service routing start > /dev/null 2> /dev/null
  exit 0            
fi                  
                  
                   
if [ ${firewall} = "ipfw" ]; then
                    
  # Chech to see if selected firewall kernel modules have been loaded.
  if ! kldstat -v | grep -qw ${firewall}; then
    echo "Error: ${firewall} was not compiled into the kernel."
    exit 2          
  fi                
                    
  # If ipfw firewall was selected in config -v
  # Get the epairXb interface name of the vnet jail and
  # write the vaule to a file so the epairXb interface name can be
  # passed to the ipfw.rules file, then start ipfw.
  # Start services inside of jail needed by ipfw firewall.
  # Note: using service command because it's not nojail keyword aware.
  #                 
  jexec ${jailname} service netif start > /dev/null 2> /dev/null
  jexec ${jailname} service routing start > /dev/null 2> /dev/null
  ipfw_epair="/usr/jails/${jailname}/etc/epair"
  jexec ${jailname} ifconfig | grep -m 1 epair | cut -f 1 -d : > ${ipfw_epair}
  jexec ${jailname} service ipfw start > /dev/null 2> /dev/null
  exit 0
fi                  
                     
                                   
if [ ${firewall} = "pf" ]; then
                   
  # Chech to see if selected firewall kernel modules have been loaded.
  if ! kldstat -v | grep -qw ${firewall}; then
    echo "Error: ${firewall} was not compiled into the kernel."
    exit 2           
  fi                
                   
  # If pf firewall was selected in config -v  
  # Get the epairXb interface name of the vnet jail and
  # write the vaule to a file so the epairXb interface name can be
  # passed to the pf.rules file, then start pf.
  # Start services inside of jail needed by pf firewall.
  # Note: using service command because it's not nojail keyword aware.
  #               
  jexec ${jailname} service netif start > /dev/null 2> /dev/null
  jexec ${jailname} service routing start > /dev/null 2> /dev/null
  pf_epair="/usr/jails/${jailname}/etc/epair"
  jexec ${jailname} ifconfig | grep -m 1 epair | cut -f 1 -d : > ${pf_epair}
  jexec ${jailname} service pf start > /dev/null 2> /dev/null
# jexec ${jailname} pfctl -F all; pfctl -f /etc/pf.rules
fi                 
                     
if [ ${firewall} = "ipfilter" ]; then
  ####### This stub is not used. Coded for when ipfilter becomes vnet aware.
  # If ipfilter firewall was selected in config -v
  # Get the epairXb interface name of the vnet jail and
  # write the vaule to a file so the epairXb interface name can be
  # passed to the pf.rules file, then start pf.
  # Start services inside of jail needed by ipfilter firewall.
  # Note: using service command because it's not nojail keyword aware.
  #               
  jexec ${jailname} service netif start > /dev/null 2> /dev/null
  jexec ${jailname} service routing start > /dev/null 2> /dev/null
  ipf_epair="/usr/jails/${jailname}/etc/epair"
  jexec ${jailname} ifconfig | grep -m 1 epair | cut -f 1 -d : > ${ipf_epair}
  jexec ${jailname} service ipfilter start > /dev/null 2> /dev/null
fi            
            
}           
               
          
stop () {       
               
# Disable vnet jails network configuration.
#          
jid=`jls -j ${jailname} jid`
ifconfig epair${jid}b -vnet ${jid}
ifconfig bridge0 -alias 10.${jid}.0.1
ifconfig epair${jid}a destroy
          
# If host has no more vnet jails then disable bridge.
#         
epair=`ifconfig | grep -m 1 epair | cut -f 1 -d :`
if [ -z ${epair} ]; then
  ifconfig bridge0 destroy
  sysctl net.inet.ip.forwarding=0 > /dev/null 2> /dev/null
fi            
                                
if [ ${firewall} = "ipfw" ]; then
  # If ipfw was started, now disable it.
  #                   
  jexec ${jailname} service ipfw stop > /dev/null 2> /dev/null
  jexec ${jailname} service routing stop > /dev/null 2> /dev/null
  jexec ${jailname} service netif stop > /dev/null 2> /dev/null
  sleep 2         
fi               
               
if [ ${firewall} = "pf" ]; then
  # If pf was started, now disable it.
  #               
  jexec ${jailname} service pf stop > /dev/null 2> /dev/null
  jexec ${jailname} service routing stop > /dev/null 2> /dev/null
  jexec ${jailname} service netif stop > /dev/null 2> /dev/null
  sleep 2        
fi                
                
if [ ${firewall} = "ipfilter" ]; then
  ######### This stub is not used right now.
  # If ipfilter was started, now disable it.
  #          
  jexec ${jailname} service ipfilter stop > /dev/null 2> /dev/null
  jexec ${jailname} service routing stop > /dev/null 2> /dev/null
  jexec ${jailname} service netif stop > /dev/null 2> /dev/null
  sleep 2              
fi             
            
if [ ${firewall} = "none" ]; then
  # If no firewall was started, disable network.
  #         
  jexec ${jailname} service routing stop > /dev/null 2> /dev/null
  jexec ${jailname} service netif stop > /dev/null 2> /dev/null
  sleep 2
fi          
           
}            
                
[ "${function}" = "start" ]   && start   $*  && exit 0
[ "${function}" = "stop" ]    && stop    $*  && exit 0
              
