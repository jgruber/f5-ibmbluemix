#!/bin/bash

#### Settings ####

# TMOS Virtual edition well known account settings

[[ -z $TMOS_ADMIN_PASSWORD ]] && TMOS_ADMIN_PASSWORD="ibmsoftlayer"
[[ -z $TMOS_ROOT_PASSWORD ]] && TMOS_ROOT_PASSWORD="ibmsoftlayer"

# Disk image and metadata templates

[[ -z $BIGIP_UNZIPPED_QCOW_IMAGE_URL ]] && BIGIP_UNZIPPED_QCOW_IMAGE_URL="file:///tmp/BIGIP-13.1.0.3.0.0.5.qcow2"
[[ -z $TMOS_VE_DOMAIN_TEMPLATE ]] && TMOS_VE_DOMAIN_TEMPLATE="file:///tmp/ve_domain_3_nic_virtio_mq_xml.tmpl"
[[ -z $USER_DATA_URL ]] && USER_DATA_URL="file:///tmp/ibm_init_userdata.txt"

# Portable network setup

[[ -z $PORTABLE_PRIVATE_ADDRESS ]] && PORTABLE_PRIVATE_ADDRESS=""
[[ -z $PORTABLE_PRIVATE_NETMASK ]] && PORTABLE_PRIVATE_NETMASK=""
[[ -z $PORTABLE_PRIVATE_GATEWAY ]] && PORTABLE_PRIVATE_GATEWAY=""

[[ -z $PORTABLE_PUBLIC_ADDRESS ]] && PORTABLE_PUBLIC_ADDRESS=""
[[ -z $PORTABLE_PUBLIC_NETMASK ]] && PORTABLE_PUBLIC_NETMASK=""
[[ -z $PORTABLE_PUBLIC_GATEWAY ]] && PORTABLE_PUBLIC_GATEWAY=""

[[ -z $TMOS_LICENSE_BASEKEY ]] && TMOS_LICENSE_BASEKEY=""
[[ -z $TMOS_AS3_URL ]] && TMOS_AS3_URL="https://github.com/F5Networks/f5-appsvcs-extension/releases/download/3.0.0/f5-appsvcs-3.0.0-34.noarch.rpm"

#### End Settings ####

function install_hypervisor() {
    yum -y install qemu-kvm libvirt virt-install bridge-utils iptables-services genisoimage python-yaml
    systemctl enable iptables.service
    systemctl start libvirtd.service
    /sbin/sysctl -w net.ipv4.ip_forward=1
    echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
    chkconfig NetworkManager off
}

function get_config_drive_template() {
    mkdir -p /tmp/config_drive/openstack/latest
    create_meta_data_json > /tmp/config_drive/openstack/latest/meta_data.json
    python -m json.tool < /tmp/config_drive/openstack/latest/meta_data.json > /dev/null 2>&1
    if [ $? -ne 0 ];
    then
        echo "ERROR: Generated meta_data.json was not valid. Exiting.."
        cleanup_and_exit
    fi
    create_network_json > /tmp/config_drive/openstack/latest/network_data.json
    python -m json.tool < /tmp/config_drive/openstack/latest/network_data.json > /dev/null 2>&1
    if [ $? -ne 0 ];
    then
        echo "ERROR: Generated network_data.json was not valid. Exiting.."
        cleanup_and_exit
    else
        echo
        echo "Generated network metadata is:"
        echo
        cat  /tmp/config_drive/openstack/latest/network_data.json
        echo
        echo
    fi
    if ! [ -f /tmp/config_drive/openstack/latest/user_data ]; then
        curl -o /tmp/config_drive/openstack/latest/user_data $USER_DATA_URL
        if [ $? -ne 0 ];
        then
            echo "ERROR: Could not retrieve user_data template from: $USER_DATA_URL. Exiting.."
            cleanup_and_exit
        fi
    fi
    python -c 'import yaml,sys;yaml.safe_load(sys.stdin)' < /tmp/config_drive/openstack/latest/user_data > /dev/null 2>&1
    if [ $? -ne 0 ];
    then
        echo "ERROR: The user_data template was not valid. Exiting.."
        cleanup_and_exit
    fi
    sed -i -e "s/__TMOS_ADMIN_PASSWORD__/$TMOS_ADMIN_PASSWORD/g" /tmp/config_drive/openstack/latest/user_data
    sed -i -e "s/__TMOS_ROOT_PASSWORD__/$TMOS_ROOT_PASSWORD/g" /tmp/config_drive/openstack/latest/user_data
    sed -i -e "s/__TMOS_LICENSE_BASEKEY__/$TMOS_LICENSE_BASEKEY/g" /tmp/config_drive/openstack/latest/user_data
    sed -i -e "s#__TMOS_AS3_URL__#$TMOS_AS3_URL#g" /tmp/config_drive/openstack/latest/user_data
}

function get_ve_domain_template() {
    if ! [ -f /tmp/ve_domain_xml.tmpl ]; then
        curl -o /tmp/ve_domain_xml.tmpl $TMOS_VE_DOMAIN_TEMPLATE
        if [ $? -ne 0 ];
        then
            echo "ERROR: Could not retrieve libvirt domain XML template from: $TMOS_VE_DOMAIN_TEMPLATE. Exiting.."
            cleanup_and_exit
        fi
    fi
}

function get_ve_image() {
    if ! [ -f /var/lib/libvirt/images/bigipve.qcow2 ]; then
        curl -o /var/lib/libvirt/images/bigipve.qcow2 $BIGIP_UNZIPPED_QCOW_IMAGE_URL
        if [ $? -ne 0 ];
        then
            echo "ERROR: Could not retrieve TMOS Virtual Edition disk image from: $BIGIP_UNZIPPED_QCOW_IMAGE_URL. Exiting.."
            cleanup_and_exit
        fi
        is_qcow=$(qemu-img info /var/lib/libvirt/images/bigipve.qcow2 | grep "format: qcow2" | wc -l)
        if [ $is_qcow -ne 1 ];
        then
            echo "ERROR: The image file: $BIGIP_UNZIPPED_QCOW_IMAGE_URL, is not a qcow2 disk image. Did you unzip? Exiting.."
            cleanup_and_exit
        fi
    fi
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

function create_macvtap_scripts() {
    upscript='/etc/sysconfig/network-scripts/ifup-macvlan'
    cat > $upscript <<EOF
. /etc/init.d/functions
cd /etc/sysconfig/network-scripts
. ./network-functions
[ -f ../network ] && . ../network
CONFIG=${1}
need_config ${CONFIG}
source_config
OTHERSCRIPT="/etc/sysconfig/network-scripts/ifup-${REAL_DEVICETYPE}"
if [ ! -x ${OTHERSCRIPT} ]; then
    OTHERSCRIPT="/etc/sysconfig/network-scripts/ifup-eth"
fi
ip link add link ${MACVLAN_PARENT} name ${DEVICE} type ${TYPE:-macvlan} mode ${MACVLAN_MODE:-private}
${OTHERSCRIPT} ${CONFIG}
EOF
    downscript='/etc/sysconfig/network-scripts/ifdown-macvlan'
    cat > $downscript <<EOF
. /etc/init.d/functions
cd /etc/sysconfig/network-scripts
. ./network-functions
[ -f ../network ] && . ../network
CONFIG=${1}
need_config ${CONFIG}
source_config
OTHERSCRIPT="/etc/sysconfig/network-scripts/ifup-${REAL_DEVICETYPE}"
if [ ! -x ${OTHERSCRIPT} ]; then
    OTHERSCRIPT="/etc/sysconfig/network-scripts/ifdown-eth"
fi
${OTHERSCRIPT} ${CONFIG}
ip link del ${DEVICE} type ${TYPE:-macvlan}
EOF
    chmod +x $upscript
    chmod +x $downscript
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
    private_interface=$(get_private_interface);
    private_mtu=$(cat /sys/class/net/$private_interface/mtu)
    private_mac_address=$(cat /sys/class/net/$private_interface/address)
    private_mvtap_mac=$(echo "02${private_mac_address:2:15}")
    private_ip_address=$(cat /etc/sysconfig/network-scripts/ifcfg-$private_interface|grep IPADDR|cut -d= -f2)
    if [ ! -z $PORTABLE_PRIVATE_ADDRESS ]; then
        private_ip_address=$PORTABLE_PRIVATE_ADDRESS
    fi
    private_netmask=$(cat /etc/sysconfig/network-scripts/ifcfg-$private_interface|grep NETMASK|cut -d= -f2)
    if [ ! -z $PORTABLE_PRIVATE_NETMASK ]; then
        private_netmask=$PORTABLE_PRIVATE_NETMASK
    fi
    private_default_gateway=$(cat /etc/sysconfig/network-scripts/ifcfg-$private_interface|grep GATEWAY|cut -d= -f2)
    if [ ! -z $PORTABLE_PRIVATE_GATEWAY ]; then
        private_default_gateway=$PORTABLE_PRIVATE_GATEWAY
    fi
    private_routes=""
    if [ ! -z $PORTABLE_PRIVATE_GATEWAY ]; then
        if [ -f /etc/sysconfig/network-scripts/route-$private_interface ]; then
            while read route; do
                network=$(echo $route|cut -d' ' -f1)
                private_routes="${private_routes} ${network}:${private_default_gateway}"
            done <<< "$(cat /etc/sysconfig/network-scripts/route-"$private_interface")"
        fi
    else
        if [ -f /etc/sysconfig/network-scripts/route-$private_interface ]; then
            while read route; do
                network=$(echo $route|cut -d' ' -f1)
                gateway=$(echo $route|cut -d' ' -f3)
                private_routes="${private_routes} ${network}:${gateway}"
            done <<< "$(cat /etc/sysconfig/network-scripts/route-"$private_interface")"
        fi
    fi
    public_interface=$(get_public_interface);
    public_routes=""
    if [ $private_interface != $public_interface ]; then
        public_mac_address=$(cat /sys/class/net/$public_interface/address)
        public_mvtap_mac=$(echo "02${public_mac_address:2:15}")
        public_mtu=$(cat /sys/class/net/$public_interface/mtu)
        public_ip_address=$(cat /etc/sysconfig/network-scripts/ifcfg-$public_interface|grep IPADDR|cut -d= -f2)
        if [ ! -z $PORTABLE_PUBLIC_ADDRESS ]; then
            public_ip_address=$PORTABLE_PUBLIC_ADDRESS
        else
            if [ -f /etc/sysconfig/network-scripts/route-$public_interface ]; then
                while read route; do
                    network=$(echo $route|cut -d' ' -f1)
                    gateway=$(echo $route|cut -d' ' -f3)
                    public_routes="${public_routes} ${network}:${gateway}"
                done <<< "$(cat /etc/sysconfig/network-scripts/route-"$public_interface")"
            fi
        fi
        public_netmask=$(cat /etc/sysconfig/network-scripts/ifcfg-$public_interface|grep NETMASK|cut -d= -f2)
        if [ ! -z $PORTABLE_PUBLIC_NETMASK ]; then
            public_netmask=$PORTABLE_PUBLIC_NETMASK
        fi
        public_default_gateway=$(cat /etc/sysconfig/network-scripts/ifcfg-$public_interface|grep GATEWAY|cut -d= -f2)
        if [ ! -z $PORTABLE_PUBLIC_GATEWAY ]; then
            public_default_gateway=$PORTABLE_PUBLIC_GATEWAY
        fi
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
    echo -n "{ \"id\": \"management_link\", \"name\": \"veth0\", \"mtu\": \"1500\", \"type\": \"phy\", \"ethernet_mac_address\": \"02:00:00:00:00:01\"},"
    echo -n "{ \"id\": \"private_link\", \"name\": \"${private_interface}\", \"mtu\": \"${private_mtu}\", \"type\": \"phy\", \"ethernet_mac_address\": \"${private_mvtap_mac}\"}"
    if [ $private_interface != $public_interface ]; then
        echo -n ", "
        echo -n "{ \"id\": \"public_link\", \"name\": \"${public_interface}\", \"mtu\": \"${public_mtu}\", \"type\": \"phy\", \"ethernet_mac_address\": \"${public_mvtap_mac}\"}"
    fi
    echo -n "], "
    #end links
    #start networks
    echo -n "\"networks\": [ "
    echo -n "{ \"id\": \"mgmt\", \"link\": \"management_link\", \"type\": \"ipv4_dhcp\"},"
    echo -n "{ \"id\": \"private\", \"link\": \"private_link\", \"type\": \"ipv4\", \"ip_address\": \"${private_ip_address}\", \"netmask\": \"${private_netmask}\", "
    echo -n "\"routes\": ["
    private_route_json=""
    # if [[ ! -z "${private_default_gateway}" ]]; then
    #    private_route_json=" { \"network\": \"0.0.0.0\", \"netmask\": \"0.0.0.0\", \"gateway\": \"${private_default_gateway}\" },"
    # fi
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
    echo -n "] }"
    if [ $private_interface != $public_interface ]; then
        echo -n ", "
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
        echo -n "] }"
    fi
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

function configure_bridge_forwarding() {
    cat >> /etc/sysctl.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 0
net.bridge.bridge-nf-call-iptables = 0
net.bridge.bridge-nf-call-arptables = 0
EOF
    /usr/sbin/iptables -I FORWARD -m physdev --physdev-is-bridged -j ACCEPT
    /usr/libexec/iptables/iptables.init save
}

function migrate_private_interface() {
    private_interface=$(get_private_interface)
    /usr/bin/cp -f /etc/sysconfig/network-scripts/ifcfg-$private_interface /etc/sysconfig/network-scripts/dist-ifcfg-$private_interface
    /usr/bin/cp -f /etc/sysconfig/network-scripts/route-$private_interface /etc/sysconfig/network-scripts/dist-route-$private_interface
    if [ -z $PORTABLE_PRIVATE_ADDRESS ]; then
        sed -i '/IPADDR/d' /etc/sysconfig/network-scripts/ifcfg-$private_interface
        sed -i '/NETMASK/d' /etc/sysconfig/network-scripts/ifcfg-$private_interface
        sed -i '/GATEWAY/d' /etc/sysconfig/network-scripts/ifcfg-$private_interface
        rm -f /etc/sysconfig/network-scripts/route-$private_interface
    fi
    for f in /etc/sysconfig/network-scripts/ifcfg-$private_interface-range*; do
        mv -f $f /etc/sysconfig/network-scripts/dist-$f
    done
}

function migrate_public_interface() {
    private_interface=$(get_private_interface)
    public_interface=$(get_public_interface)
    if [ $private_interface != $public_interface ]; then
        /usr/bin/cp -f /etc/sysconfig/network-scripts/ifcfg-$public_interface /etc/sysconfig/network-scripts/dist-ifcfg-$public_interface
        /usr/bin/cp -f /etc/sysconfig/network-scripts/route-$public_interface /etc/sysconfig/network-scripts/dist-route-$public_interface
        if [ -z $PORTABLE_PUBLIC_ADDRESS ]; then
            sed -i '/IPADDR/d' /etc/sysconfig/network-scripts/ifcfg-$public_interface
            sed -i '/NETMASK/d' /etc/sysconfig/network-scripts/ifcfg-$public_interface
            sed -i '/GATEWAY/d' /etc/sysconfig/network-scripts/ifcfg-$public_interface
            rm -f /etc/sysconfig/network-scripts/route-$public_interface
        fi
        for f in /etc/sysconfig/network-scripts/ifcfg-$public_interface-range*; do
            mv -f $f /etc/sysconfig/network-scripts/dist-$f
        done
    fi
}

function restore_dist_networking() {
    for f in /etc/sysconfig/network-scripts/dist-*; do
        fn=$(basename $f)
        mv -f $f /etc/sysconfig/network-scripts/${fn:5}
    done
}

function remove_vm() {
    hostname=$(hostname)
    virsh destroy $hostname
    virsh undefine $hostname
}

function remove_temp_files() {
    rm -rf /tmp/config_drive
    rm -rf /tmp/ve_domain_xml.tmpl
    rm -rf /var/lib/libvirt/images/config.iso
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

function get_virtio_queue_count() {
    echo "2"
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
    virtio_queues=$(get_virtio_queue_count);
    private_interface=$(get_private_interface);
    private_mac_address=$(cat /sys/class/net/$private_interface/address)
    private_mvtap_mac=$(echo "02${private_mac_address:2:15}")
    public_interface=$(get_public_interface);
    public_mac_address=$(cat /sys/class/net/$public_interface/address)
    public_mvtap_mac=$(echo "02${public_mac_address:2:15}")
    sed -i -e "s/__HOSTNAME__/$hostname/g" /tmp/ve_domain_xml.tmpl
    sed -i -e "s/__F5_CHASIS_SERIAL_NUMBER__/$systemid/g" /tmp/ve_domain_xml.tmpl
    sed -i -e "s/__VE_RAM__/$mem/g" /tmp/ve_domain_xml.tmpl
    sed -i -e "s/__VE_CPUS__/$vcpus/g" /tmp/ve_domain_xml.tmpl
    sed -i -e "s/__TMOS_VERSION__/13.1.0/g" /tmp/ve_domain_xml.tmpl
    sed -i -e "s/__PRIVATE_MAC_ADDRESS__/$private_mvtap_mac/g" /tmp/ve_domain_xml.tmpl
    sed -i -e "s/__PRIVATE_HOST_INTERFACE__/$private_interface/g" /tmp/ve_domain_xml.tmpl
    sed -i -e "s/__VIRTIO_NIC_QUEUES__/$virtio_queues/g" /tmp/ve_domain_xml.tmpl
    sed -i -e "s/__PUBLIC_MAC_ADDRESS__/$public_mvtap_mac/g" /tmp/ve_domain_xml.tmpl
    sed -i -e "s/__PUBLIC_MAC_INTERFACE__/$public_interface/g" /tmp/ve_domain_xml.tmpl
    sed -i -e "s/__VIRTIO_NIC_QUEUES__/$virtio_queues/g" /tmp/ve_domain_xml.tmpl
    virsh define /tmp/ve_domain_xml.tmpl
    virsh autostart $hostname
}

function cleanup_and_exit() {
    rm -rf /tmp/config_drive > /dev/null 2>&1
    rm -rf /var/lib/libvirt/images/bigipve.qcow2 > /dev/null 2>&1
    rm -rf /tmp/ve_domain_xml.tmpl > /dev/null 2>&1
    exit 1
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
    echo "######### Adding Host Configurations #########"
    create_macvtap_scripts
    configure_bridge_forwarding
    echo "######### Setting up Private Network #########"
    migrate_private_interface
    echo "######### Setting up Public Network #########"
    migrate_public_interface
    echo "######### Building libvirt VE Domain #########"
    setup_ve_host_domain
    echo "######### Building VE Config Drive #########"
    create_config_drive
    echo "######### Rebooting into Hypervisor #########"
    reboot
}

main "$@"
