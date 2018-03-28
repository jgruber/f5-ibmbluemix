#!/bin/bash

#### Settings ####

# TMOS Virtual edition well known account settings

TMOS_ADMIN_PASSWORD="ibmsoftlayer"
TMOS_ROOT_PASSWORD="ibmsoftlayer"

# Github repo and branch for KVM environment and user_data templates

REPO="jgruber"
BRANCH="master"

BIGIP_UNZIPPED_QCOW_IMAGE_URL="file:///tmp/BIGIP-13.1.0.3.0.0.5.LTM_1SLOT.qcow2"
TMOS_VE_DOMAIN_TEMPLATE="https://raw.githubusercontent.com/$REPO/f5-ibmbluemix/$BRANCH/ve_domain_xml.tmpl"
USER_DATA_URL="https://raw.githubusercontent.com/$REPO/f5-ibmbluemix/$BRANCH/ibm_init_userdata.txt"

#### End Settings ####

function install_hypervisor() {
    yum -y install qemu-kvm libvirt virt-install bridge-utils iptables-services genisoimage
    systemctl enable iptables.service
    systemctl start libvirtd.service
    /sbin/sysctl -w net.ipv4.ip_forward=1
    echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
    chkconfig NetworkManager off 
}

function get_config_drive_template() {
    mkdir -p /tmp/config_drive/openstack/latest
    create_meta_data_json > /tmp/config_drive/openstack/latest/meta_data.json
    create_network_json > /tmp/config_drive/openstack/latest/network_data.json
    wget -nc -O /tmp/config_drive/openstack/latest/user_data $USER_DATA_URL
    sed -i -e "s/__TMOS_ADMIN_PASSWORD__/$TMOS_ADMIN_PASSWORD/g" /tmp/config_drive/openstack/latest/user_data
    sed -i -e "s/__TMOS_ROOT_PASSWORD__/$TMOS_ROOT_PASSWORD/g" /tmp/config_drive/openstack/latest/user_data
}

function get_ve_domain_template() {
    wget -nc -O /tmp/ve_domain_xml.tmpl $TMOS_VE_DOMAIN_TEMPLATE
}

function get_ve_image() {
    wget -nc -O /var/lib/libvirt/images/bigipve.qcow2 $BIGIP_UNZIPPED_QCOW_IMAGE_URL
}

function get_public_interface() {
    public_interface=$(ip route|grep default|cut -d' ' -f5);
    echo $public_interface  
}

function get_private_interface() {
    private_interface=$(ip route|grep 10.0.0.0/8|cut -d' ' -f5);
    echo $private_interface 
}

function cidr2mask() {
  local i mask=""
  local full_octets=$(($1/8))
  local partial_octet=$(($1%8))
  for ((i=0;i<4;i+=1)); do
    if [ $i -lt $full_octets ]; then
      mask+=255
    elif [ $i -eq $full_octets ]; then
      mask+=$((256 - 2**(8-$partial_octet)))
    else
      mask+=0
    fi  
    test $i -lt 3 && mask+=.
  done
  echo $mask
}

function create_meta_data_json() {
    hostname=$(hostname);
    echo -n "{ ";
    echo -n "\"hostname\": \"$hostname\",";
    echo -n "\"name\": \"$hostname\",";
    system_uuid=$(create_system_id);
    echo -n "\"uuid\": \"$system_uuid\",";
    echo -n "\"public_keys\": { ";
    local keyfile="$HOME/.ssh/authorized_keys"
    key_index=0;
    keys="";
    while read key; do
        key_index=$[key_index+1]
        keys="$keys \"adminkey_${key_index}\": \"${key}\",";
    done < "${keyfile}"
    if [ ! -z "${keys}" ]; then
        echo -n "${keys::-1}"
    fi
    echo -n "} }";
}

function create_network_json() {
    public_interface=$(get_public_interface);
    public_mac_address=$(cat /sys/class/net/$public_interface/address)
    public_mtu=$(cat /sys/class/net/$public_interface/mtu)
    public_ip_address=$(cat /etc/sysconfig/network-scripts/ifcfg-$public_interface|grep IPADDR|cut -d= -f2)
    public_netmask=$(cat /etc/sysconfig/network-scripts/ifcfg-$public_interface|grep NETMASK|cut -d= -f2)
    public_default_gateway=$(cat /etc/sysconfig/network-scripts/ifcfg-$public_interface|grep GATEWAY|cut -d= -f2)
    public_routes=""
    if [ -f /etc/sysconfig/network-scripts/route-$public_interface ]; then
        while read route; do
            network=$(echo $route|cut -d' ' -f1)
            gateway=$(echo $route|cut -d' ' -f3)
            public_routes="${public_routes} ${network}:${gateway}"
        done <<< "$(cat /etc/sysconfig/network-scripts/route-"$public_interface")"
    fi
    private_interface=$(get_private_interface);
    private_mtu=$(cat /sys/class/net/$private_interface/mtu)
    private_mac_address=$(cat /sys/class/net/$private_interface/address)
    private_ip_address=$(cat /etc/sysconfig/network-scripts/ifcfg-$private_interface|grep IPADDR|cut -d= -f2)
    private_netmask=$(cat /etc/sysconfig/network-scripts/ifcfg-$private_interface|grep NETMASK|cut -d= -f2)
    private_default_gateway=$(cat /etc/sysconfig/network-scripts/ifcfg-$private_interface|grep GATEWAY|cut -d= -f2)
    private_routes=""
    if [ -f /etc/sysconfig/network-scripts/route-$private_interface ]; then
        while read route; do
            network=$(echo $route|cut -d' ' -f1)
            gateway=$(echo $route|cut -d' ' -f3)
            private_routes="${private_routes} ${network}:${gateway}"
        done <<< "$(cat /etc/sysconfig/network-scripts/route-"$private_interface")"
    fi
    dnsservers=""
    if [ -f /etc/resolv.conf ]; then
        while read resolv; do
            entry=$(echo $resolv|grep nameserver|cut -d' ' -f2)
            dnsservers="${dnsservers} ${entry}"
        done <<< "$(cat /etc/resolv.conf)"
    fi
    #start json
    echo -n "{ "
    #start links
    echo -n "\"links\": [ "
    echo -n "{ \"id\": \"private_link\", \"name\": \"${private_interface}\", \"mtu\": \"${private_mtu}\", \"type\": \"phy\", \"ethernet_mac_address\": \"${private_mac_address}\"}"
    echo -n ", "
    echo -n "{ \"id\": \"public_link\", \"name\": \"${public_interface}\", \"mtu\": \"${public_mtu}\", \"type\": \"phy\", \"ethernet_mac_address\": \"${public_mac_address}\"}"
    echo -n "], "
    #end links
    #start networks 
    echo -n "\"networks\": [ "
    echo -n "{ \"id\": \"private\", \"link\": \"private_link\", \"type\": \"ipv4\", \"ip_address\": \"${private_ip_address}\", \"netmask\": \"${private_netmask}\", "
    echo -n "\"routes\": ["
    private_route_json=""
    if [[ ! -z "${private_default_gateway}" ]]; then
        private_route_json=" { \"network\": \"0.0.0.0\", \"netmask\": \"0.0.0.0\", \"gateway\": \"${private_default_gateway}\" },"
    fi
    if [[ ! -z "${private_routes// }" ]]; then
        private_routes=($private_routes)
        for route in "${private_routes[@]}"; do
            cidr=$(echo $route|cut -d':' -f1)
            gateway=$(echo $route|cut -d':' -f2)
            network=$(echo $cidr|cut -d'/' -f1)
            maskbits=$(echo $cidr|cut -d'/' -f2)
            netmask=$(cidr2mask $maskbits)
            private_route_json="${private_route_json} { \"network\": \"${network}\", \"netmask\": \"${netmask}\", \"gateway\": \"${gateway}\" }," 
        done
        if [[ ! -z "${private_route_json}" ]]; then
            echo -n "${private_route_json::-1} "
        fi
    fi
    echo -n "] }, "
    echo -n "{ \"id\": \"public\", \"link\": \"public_link\", \"type\": \"ipv4\", \"ip_address\": \"${public_ip_address}\", \"netmask\": \"${public_netmask}\", "
    echo -n "\"routes\": ["
    public_route_json=""
    if [[ ! -z "${public_default_gateway}" ]]; then
        public_route_json=" { \"network\": \"0.0.0.0\", \"netmask\": \"0.0.0.0\", \"gateway\": \"${public_default_gateway}\" },"
    fi
    if [[ ! -z "${public_routes// }" ]]; then
        public_routes=($public_routes)
        for route in "${public_routes[@]}"; do
            cidr=$(echo $route|cut -d':' -f1)
            gateway=$(echo $route|cut -d':' -f2)
            network=$(echo $cidr|cut -d'/' -f1)
            maskbits=$(echo $cidr|cut -d'/' -f2)
            netmask=$(cidr2mask $maskbits)
            public_route_json="${public_route_json} { \"network\": \"${network}\", \"netmask\": \"${netmask}\", \"gateway\": \"${gateway}\" }," 
        done
    fi
    if [[ ! -z "${public_route_json}" ]]; then
        echo -n "${public_route_json::-1} "
    fi
    echo -n "] } "
    echo -n "], "
    #end networks
    #start services
    echo -n "\"services\": [ "
    if [[ ! -z "${dnsservers// }" ]]; then
        dnsservers=($dnsservers)
        services_json=""
        for dns in "${dnsservers[@]}"; do
            services_json="${services_json} { \"type\": \"dns\", \"address\": \"${dns}\" },"
        done
        echo -n "${services_json::-1} "
    fi
    echo -n "]"
    #end services
    #end json
    echo " }";
}

function generate_private_bridge() {
    cat > /etc/sysconfig/network-scripts/ifcfg-private <<EOF
DEVICE=br0
TYPE=Bridge
BOOTPROTO=static
ONBOOT=yes
DELAY=0
NM_CONTROLLED=no
STP=off
EOF
cat >> /etc/sysctl.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 0
net.bridge.bridge-nf-call-iptables = 0
net.bridge.bridge-nf-call-arptables = 0
EOF
    /usr/sbin/iptables -I FORWARD -m physdev --physdev-is-bridged -j ACCEPT
    /usr/libexec/iptables/iptables.init save
}

function migrate_private_interface_to_bridge() {
    private_interface=$(get_private_interface)
    cp /etc/sysconfig/network-scripts/ifcfg-$private_interface /etc/sysconfig/network-scripts/dist-ifcfg-$private_interface
    sed -i '/IPADDR/d' /etc/sysconfig/network-scripts/ifcfg-$private_interface
    sed -i '/NETMASK/d' /etc/sysconfig/network-scripts/ifcfg-$private_interface
    echo 'BRIDGE=private' >> /etc/sysconfig/network-scripts/ifcfg-$private_interface
    mv /etc/sysconfig/network-scripts/route-$private_interface /etc/sysconfig/network-scripts/dist-route-$private_interface 
}

function generate_public_bridge() {
    cat > /etc/sysconfig/network-scripts/ifcfg-public <<EOF
DEVICE=public
TYPE=Bridge
BOOTPROTO=static
ONBOOT=yes
DELAY=0
NM_CONTROLLED=no
STP=off
EOF
}

function migrate_public_interface_to_bridge() {
    public_interface=$(get_public_interface)
    cp /etc/sysconfig/network-scripts/ifcfg-$public_interface /etc/sysconfig/network-scripts/dist-ifcfg-$public_interface
    sed -i '/IPADDR/d' /etc/sysconfig/network-scripts/ifcfg-$public_interface
    sed -i '/NETMASK/d' /etc/sysconfig/network-scripts/ifcfg-$public_interface
    sed -i '/GATEWAY/d' /etc/sysconfig/network-scripts/ifcfg-$public_interface
    echo 'BRIDGE=public' >> /etc/sysconfig/network-scripts/ifcfg-$public_interface
    mv /etc/sysconfig/network-scripts/route-$public_interface /etc/sysconfig/network-scripts/dist-route-$public_interface 
}

function create_config_drive() {
    sed -i -e "s/__ADMIN_PASSWORD__/softlayerve/g" /tmp/config_drive/openstack/latest/user_data
    sed -i -e "s/__ROOT_PASSWORD__/softlayerve/g" /tmp/config_drive/openstack/latest/user_data
    genisoimage -o /var/lib/libvirt/images/config.iso -V config-2 -J /tmp/config_drive
}

function create_system_id() {
    if [[ -z $system_uuid ]]
    then
        export system_uuid=$(uuidgen);
    fi
    echo $system_uuid
}

function generate_MAC_address() {
    echo  'import random ; mac = [ 0x02, 0x01, 0x3e, random.randint(0x00, 0x7f), random.randint(0x00, 0xff), random.randint(0x00, 0xff) ] ; print ":".join(map(lambda x: "%02x" % x, mac))'| python
}

function get_CPU_count() {
    grep -c ^processor /proc/cpuinfo
}

function get_memory() {
    memory=`cat /proc/meminfo | grep MemTotal | awk '{print $2}'`
    expr $memory - 2048000
}

function setup_ve_host_domain() {
    systemid=$(create_system_id)
    hostname=$(hostname)
    vcpus=$(get_CPU_count)
    mem=$(get_memory)
    sed -i -e "s/__HOSTNAME__/$hostname/g" /tmp/ve_domain_xml.tmpl
    sed -i -e "s/__F5_CHASIS_SERIAL_NUMBER__/$systemid/g" /tmp/ve_domain_xml.tmpl 
    sed -i -e "s/__VE_RAM__/$mem/g" /tmp/ve_domain_xml.tmpl 
    sed -i -e "s/__VE_CPUS__/$vcpus/g" /tmp/ve_domain_xml.tmpl 
    sed -i -e "s/__TMOS_VERSION__/13.1.0/g" /tmp/ve_domain_xml.tmpl
    virsh define /tmp/ve_domain_xml.tmpl
    virsh autostart $hostname
}

function main() {
    echo "######### Installing Hypervisor Host #########"
    install_hypervisor
    echo "######### Create System ID #########"
    create_system_id
    echo "######### Getting f5 VE Config Drive Template #########"
    get_config_drive_template
    echo "######### Getting f5 VE libvirt Domain Template #########"
    get_ve_domain_template
    echo "######### Getting f5 VE disk image #########"
    get_ve_image
    echo "######### Setting up Private Network #########"
    generate_private_bridge
    migrate_private_interface_to_bridge
    echo "######### Setting up Public Network #########"
    generate_public_bridge
    migrate_public_interface_to_bridge
    echo "######### Building libvirt VE Domain #########"
    setup_ve_host_domain
    echo "######### Building VE Config Drive #########"
    create_config_drive
    echo "######### Rebooting into Hypervisor #########"
    reboot
}

main "$@"
