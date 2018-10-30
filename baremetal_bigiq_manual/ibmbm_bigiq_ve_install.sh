#!/bin/bash

#### Settings ####

# Disk image and metadata templates

[[ -z $BIGIQ_UNZIPPED_QCOW_IMAGE_URL ]] && BIGIQ_UNZIPPED_QCOW_IMAGE_URL="file:///tmp/BIG-IQ-6.0.1.1.0.0.9.qcow2"
[[ -z $TMOS_VE_DOMAIN_TEMPLATE ]] && TMOS_VE_DOMAIN_TEMPLATE="file:///tmp/ve_domain_1_nic_virtio_mq_xml.tmpl"

#### End Settings ####

function install_hypervisor() {
    yum -y install qemu-kvm libvirt virt-install bridge-utils iptables-services genisoimage python-yaml
    systemctl enable iptables.service
    systemctl start libvirtd.service
    /sbin/sysctl -w net.ipv4.ip_forward=1
    echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
    chkconfig NetworkManager off
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
    if ! [ -f /var/lib/libvirt/images/bigiqve.qcow2 ]; then
        curl -o /var/lib/libvirt/images/bigiqve.qcow2 $BIGIQ_UNZIPPED_QCOW_IMAGE_URL
        if [ $? -ne 0 ];
        then
            echo "ERROR: Could not retrieve TMOS Virtual Edition disk image from: $BIGIQ_UNZIPPED_QCOW_IMAGE_URL. Exiting.."
            cleanup_and_exit
        fi
        is_qcow=$(qemu-img info /var/lib/libvirt/images/bigiqve.qcow2 | grep "format: qcow2" | wc -l)
        if [ $is_qcow -ne 1 ];
        then
            echo "ERROR: The image file: $BIGIQ_UNZIPPED_QCOW_IMAGE_URL, is not a qcow2 disk image. Did you unzip? Exiting.."
            cleanup_and_exit
        fi
    fi
}

function get_public_interface() {
    public_interface=$(ip route|grep default|cut -d' ' -f5);
    echo $public_interface
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

function migrate_public_interface() {
    public_interface=$(get_public_interface)
    if [ -f "/etc/sysconfig/network-scripts/ifcfg-$public_interface" ]; then
        /usr/bin/cp -f /etc/sysconfig/network-scripts/ifcfg-$public_interface /etc/sysconfig/network-scripts/dist-ifcfg-$public_interface
        sed -i '/IPADDR/d' /etc/sysconfig/network-scripts/ifcfg-$public_interface
        sed -i '/NETMASK/d' /etc/sysconfig/network-scripts/ifcfg-$public_interface
        sed -i '/GATEWAY/d' /etc/sysconfig/network-scripts/ifcfg-$public_interface
        echo 'BRIDGE=public' >> /etc/sysconfig/network-scripts/ifcfg-$public_interface
    fi
    for f in /etc/sysconfig/network-scripts/ifcfg-$public_interface-range*; do
        mv -f $f /etc/sysconfig/network-scripts/dist-$f
    done
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
    if [ -f /var/lib/libvirt/images/BIGIQve.qcow2 ]; then
        rm -rf /var/lib/libvirt/images/BIGIQve.qcow2
    fi
}

function remove_temp_files() {
    if [ -f /tmp/ve_domain_xml.tmpl ]; then
        rm -rf /tmp/ve_domain_xml.tmpl
    fi
}

function create_system_id() {
    if [[ -z $system_uuid ]]
    then
        export system_uuid=$(uuidgen);
    fi
    echo $system_uuid
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
    virsh define /tmp/ve_domain_xml.tmpl
    virsh autostart $hostname
}

function cleanup_and_exit() {
    rm -rf /tmp/config_drive > /dev/null 2>&1
    rm -rf /var/lib/libvirt/images/BIGIQve.qcow2 > /dev/null 2>&1
    rm -rf /tmp/ve_domain_xml.tmpl > /dev/null 2>&1
    exit 1
}

function deploy() {
    echo "######### Assuring Hypervisor Host Setup #########"
    install_hypervisor
    echo "######### Create f5 VE System ID #########"
    create_system_id
    echo "######### Getting f5 VE libvirt Domain Template #########"
    get_ve_domain_template
    echo "######### Getting f5 VE disk image #########"
    get_ve_image
    echo "######### Adding f5 VE Host Configurations #########"
    configure_bridge_forwarding
    echo "######### Setting up Public Network #########"
    generate_public_bridge
    migrate_public_interface
    echo "######### Building libvirt f5 VE Domain #########"
    setup_ve_host_domain
}

function destroy() {
    echo "######### Stopping and Removing f5 VE Instance  #########"
    remove_vm
    echo "######### Restoring Distribution Networking  #########"
    restore_dist_networking
    echo "######### Removing Temporary Deployment Files #########"
    remove_temp_files
}

function main() {
    if [ "$1" == "deploy" ]
    then
       echo ""
       echo "######### Deploying f5 VE Instance #########"
       echo ""
       deploy
       if [ "$2" == "noreboot" ]
       then
           echo "######### Restarting Host Networking #########"
           systemctl restart network.service
           echo "######### Starting f5 VE Virtual Domain #########"
           virsh start $(hostname)
       else
           echo "######### Rebooting into Hypervisor #########"
           nohup reboot &> /tmp/nohup.out </dev/null &
           exit
       fi
    elif [ "$1" ==  "destroy"  ]
    then
       echo ""
       echo "######### Destroying f5 VE Deployment #########"
       echo ""
       destroy
       if [ "$2" == "noreboot" ]
       then
           echo "######### Restarting Host Networking #########"
           systemctl restart network.service
       else
           echo "######### Rebooting into Hypervisor #########"
           nohup reboot &> /tmp/nohup.out </dev/null &
           exit
       fi
    else
       echo ""
       echo "######### Deploying f5 VE Instance (Default) #########"
       echo ""
       deploy
       if [ "$2" == "noreboot" ]
       then
           echo "######### Restarting Host Networking #########"
           systemctl restart network.service
           echo "######### Starting f5 VE Virtual Domain #########"
           virsh start $(hostname)
       else
           echo "######### Rebooting into Hypervisor #########"
           nohup reboot &> /tmp/nohup.out </dev/null &
           exit
       fi
    fi
}

main "$@"
