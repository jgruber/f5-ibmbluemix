#!/bin/bash
function check_mcpd_up() {
    checks=0
    while [ $checks -lt 120 ]; do
        if tmsh -a show sys mcp-state field-fmt 2> /dev/null | grep -q running; then
            break
        fi
        let checks=checks+1
        sleep 10
    done
}
function setup_init() {
    echo "initializing setup"
    mount_config_drive
    check_mcpd_up
}
function is_onenic() {
    check_mcpd_up
    tmsh list net interface 1.0 > /dev/null 2>&1
    return $?
}
function setup_passwords() {
    echo "changing well known account passwords"
    if [[ -n $admin_password ]]; then /usr/bin/passwd admin $admin_password >/dev/null 2>&1; fi
    if [[ -n $root_password ]]; then /usr/bin/passwd root $root_password >/dev/null 2>&1; fi
}
function mount_config_drive() {
	blkid /dev/`lsblk -l -o NAME,LABEL|grep config-2|cut -d' ' -f1` > /dev/null
    configDriveSrc=$(blkid -t LABEL="config-2" -odevice)
    if [[ ! -z $configDriveSrc ]]; then
        mounted=$(cat /proc/mounts | grep $configDriveSrc | wc -l)
        if [[ $mounted == 0 ]]; then
            configDriveDest="/mnt/config"
            mkdir -p $configDriveDest
            mount "$configDriveSrc" $configDriveDest >/dev/null 2>&1
        fi
    fi
}
function setup_static_management_interface() {
    echo "configuring management interface statically"
    if [ -f /config/static_management_setup.py ]; then
        /usr/bin/python /config/static_management_setup.py
        tmsh save sys config > /dev/null
    fi
    if [ -f /config/static_management_setup.sh ]; then
        /bin/bash /config/static_management_setup.sh
        tmsh save sys config > /dev/null
    fi
}
function setup_host() {
    echo "setting up host configurations"
    if [ -f /config/host_setup.py ]; then
        /usr/bin/python /config/host_setup.py
        tmsh save sys config > /dev/null
    fi
    if [ -f /config/host_setup.sh ]; then
        /bin/bash /config/host_setup.sh
        tmsh save sys config > /dev/null
    fi
}
function setup_networking() {
    echo "setting up network configurations"
    if [ -f /config/network_setup.py ]; then
       /usr/bin/python /config/network_setup.py
       tmsh save sys config > /dev/null
    fi
    if [ -f /config/network_setup.sh ]; then
       /bin/bash /config/network_setup.sh
       tmsh save sys config > /dev/null
    fi
}
function setup_services() {
    echo "setting up service configurations"
    if [ -f /config/services_setup.py ]; then
       /usr/bin/python /config/services_setup.py
       tmsh save sys config > /dev/null
    fi
    if [ -f /config/services_setup.sh ]; then
       /bin/bash /config/services_setup.sh
       tmsh save sys config > /dev/null
    fi
}
function setup_configsync() {
    echo "setting device config sync"
    if [ -f /config/configsync_setup.py ]; then
        /usr/bin/python /config/configsync_setup.py
        tmsh save sys config > /dev/null
    fi
    if [ -f /config/configsync_setup.sh ]; then
        /bin/bash /config/configsync_setup.sh
        tmsh save sys config > /dev/null
    fi	
}
function setup_license() {
    if [[ -n $license_basekey ]]; then
        echo "licensing BIG-IP using license key $license_basekey..."
        /usr/local/bin/SOAPLicenseClient --basekey $license_basekey 2>&1
        sleep 10
    fi
}
function install_rpm() {
    if [[ -n $1 ]]; then
        for i in 1 2 3 4 5 6 7 8 9 10; do
            echo "installation attempt $i for $1"
            rpm -i $1 && break || sleep 5
        done
    fi
}
function setup_cleanup() {
    echo "cleaning up setup"
    umount /mnt/config >/dev/null 2>&1
    mtu=`cat /sys/class/net/eth0/mtu`
    ip link set eth0 mtu 1500
    check_mcpd_up
    tmsh save sys config > /dev/null
    check_mcpd_up
    ip link set eth0 mtu $mtu
}
