#!/bin/env/python
import os, json, socket, subprocess
nmd = json.load(open('/mnt/config/openstack/latest/network_data.json'))
md = json.load(open('/mnt/config/openstack/latest/meta_data.json'))
def is_v6(n):
    try:
        socket.inet_pton(socket.AF_INET6, n)
        return True
    except socket.error:
        return False
def is_v4(n):
    try:
        socket.inet_pton(socket.AF_INET, n)
        return True
    except socket.error:
        return False
onenic = False
fnull = open(os.devnull, 'w')
is_1nic = subprocess.call(['/usr/bin/tmsh', 'list', 'net', 'interface', '1.0'], stdout=fnull)
if is_1nic == 0:
    onenic = True
with open('/config/network_setup.sh', 'w') as ns:
    ns.write("#!/bin/bash\n")
    if onenic:
        ns.write("tmsh modify sys httpd ssl-port 8443\n")
        ns.write("tmsh modify net self-allow defaults add { tcp:8443 }\n")
    ln_types = ['phy', 'bridge', 'ovs', 'vif', 'tap']
    n_types = ['ipv4', 'ipv6']
    d_gw = m_dhcp = False
    m_l_id = m_ip = m_nm = m_gw = None
    links, selfips, routes = {}, {}, {}
    n_idx = 0
    for l in nmd['links']:
        if not l['mtu']:
            l['mtu'] = 1500
        if n_idx == 0:
            m_l_id = l['id']
            n_idx += 1
            continue
        if l['type'] in ln_types:
            links[l['id']] = {
                'net_name': 'net_1_%s' % n_idx,
                'mtu': l['mtu'],
                'interface': '1.%s' % n_idx,
                'interface_index': n_idx,
                'segmentation_id': 4094 - n_idx,
                'tagged': False,
                'route_domain': 0
            }
        n_idx += 1
    for l in nmd['links']:
        if l['type'] == 'vlan':
            if l['vlan_link'] not in links:
                print "VLAN %s defined for unsupported link %s" % (l['vlan_id'], l['vlan_link'])
            else:
                if not onenic and links[l['vlan_link']]['interface_index'] == 0:
                    print "VLAN tagging is not supported on management interface"
                else:
                    links[l['id']] = {
                        'net_name': 'vlan_%s' % l['vlan_id'],
                        'mtu': links[l['vlan_link']]['mtu'],
                        'interface': links[l['vlan_link']]['interface'],
                        'interface_index': links[l['vlan_link']]['interface_index'],
                        'segmentation_id': l['vlan_id'],
                        'tagged': True, 'route_domain': 0
                    }
    for n in nmd['networks']:
        if n['link'] == m_l_id:
            if n['type'] == 'ipv4_dhcp' or n['type'] == 'ipv6_dhcp':
                m_ip = subprocess.Popen(
                    "egrep -m 1 -A 1 mgmt /var/lib/dhclient/dhclient.leases | grep fixed-address | cut -d' ' -f4 | tr -d ';\n'",
                    stdout=subprocess.PIPE, shell=True).communicate()[0]
                m_nm = subprocess.Popen(
                    "egrep -m 1 -A 2 mgmt /var/lib/dhclient/dhclient.leases | grep subnet-mask | cut -d' ' -f5 | tr -d ';\n'",
                    stdout=subprocess.PIPE, shell=True).communicate()[0]
                m_dhcp = True
        if n['type'] in n_types:
            for r in n['routes']:
                if d_gw:
                    for l in links:
                        links[l]['route_domain'] = links[l]['segmentation_id']
                if r['network'] == '0.0.0.0' or r['network'] == '::':
                    if n['link'] == m_l_id:
                        m_gw = r['gateway']
                        if onenic:
                            d_gw = True
                        continue
                    elif n['link'] in links:
                        d_gw = True
            for r in n['routes']:
                if n['link'] in links:
                    r['route_domain'] = links[n['link']]['route_domain']
                    r['route_name'] = "route_%s" % r['network'].replace('.', '_').replace(':', '_').replace('/', '_')
                    if n['id'] not in routes:
                        routes[n['id']] = []
                    if r['network'] == '0.0.0.0' or r['network'] == '::':
                        if r['gateway'] != m_gw:
                            routes[n['id']].append(r)
                    else:
                        routes[n['id']].append(r)
            if n['link'] in links:
                netmask = None
                if 'netmask' in n:
                    netmask = n['netmask']
                if not n['link'] == m_l_id:
                    selfips[n['id']] = {
                        'selfip_name': 'selfip_%s' % n['link'],
                        'net_name': links[n['link']]['net_name'],
                        'ip_address': n['ip_address'],
                        'netmask': netmask,
                        'route_domain': links[n['link']]['route_domain']
                    }
            if n['link'] == m_l_id:
                m_ip = n['ip_address']
                if 'netmask' in n:
                    m_nm = n['netmask']
    if not m_dhcp:
        ns.write("tmsh modify sys global-settings mgmt-dhcp disabled\n")
        if onenic:
            ns.write("tmsh create sys management-ip %s/%s\n" % (m_ip, m_nm))
            ns.write("tmsh create net vlan internal { interfaces replace-all-with { 1.0 { } } tag 4094 }\n")
            ns.write("tmsh create net self self_1nic { address %s/%s allow-service default vlan internal }\n" % (m_ip, m_nm))
            if m_gw:
                ns.write("tmsh create sys management-route default gateway %s\n" % m_gw)
                ns.write("tmsh create net route default network default gw %s\n" % m_gw)
        else:
            ns.write("sleep 10\n")
            if m_nm:
                ns.write("tmsh create sys management-ip %s/%s\n" % (m_ip, m_nm))
            else:
                ns.write("tmsh create sys management-ip %s\n" % m_ip)
            if m_gw:
                ns.write("tmsh create sys management-route default gateway %s\n" % m_gw)
            ns.write("ip link set mgmt mtu %s\n" % links[m_l_id]['mtu'])
            ns.write("echo 'ip link set mgmt mtu %s' > /config/startup\n" % links[m_l_id]['mtu'])
    if onenic:
        with open('/config/configsync_setup.sh', 'w') as cs:
            cs.write("tmsh show net self self_1nic > /dev/null 2>&1; while [ \$? -ne 0 ]; do sleep 2; tmsh show net self self_1nic > /dev/null 2>&1; done\n")
            cs.write("tmsh modify /sys db configsync.allowmanagement value enable\n")
            cs.write("tmsh modify cm device %s configsync-ip %s unicast-address { { effective-ip %s effective-port 1026 ip %s } }\n" % (
                md['hostname'], m_ip, m_ip, m_ip))
    for l_id in links:
        l = links[l_id]
        if l_id == m_l_id:
            continue
        if not l['tagged']:
            ns.write("tmsh create net vlan %s mtu %s interfaces replace-all-with { %s } tag %s\n" % (
                l['net_name'], l['mtu'], l['interface'], l['segmentation_id']))
        else:
            ns.write("tmsh create net vlan %s mtu %s interfaces replace-all-with { %s { tagged } } tag %s\n" % (
                l['net_name'], l['mtu'], l['interface'], l['segmentation_id']))
        if l['route_domain'] > 0:
            ns.write("tmsh create net route-domain %s { id %s vlans add { %s } }\n" % (
                l['route_domain'], l['route_domain'], l['net_name']))
    for n_id in selfips:
        s = selfips[n_id]
        sip = s['ip_address']
        snm = None
        if s['netmask']:
            snm = s['netmask']
        else:
            ap = s['ip_address'].split('/')
            sip = ap[0]
            snm = ap[1]
        ns.write("tmsh create net self %s address %s%%%s/%s vlan %s allow-service all\n" % (s['selfip_name'], sip, s['route_domain'], snm, s['net_name']))
        if (not onenic) and (links[n_id]['interface'] == '1.1'):
            with open('/config/configsync_setup.sh', 'w') as cs:
                cs.write("tmsh show net self %s > /dev/null 2>&1; while [ \$? -ne 0 ]; do sleep 2; tmsh show net self %s > /dev/null 2>&1; done\n" % (
                    s['selfip_name'], s['selfip_name']))
                cs.write("tmsh modify cm device %s configsync-ip %s unicast-address { { effective-ip %s effective-port 1026 ip %s } } mirror-ip %s\n" % (
                    md['hostname'], sip, sip, sip, sip))
    for n_id in routes:
        for r in routes[n_id]:
            if r['network'] == '0.0.0.0' or r['network'] == '::':
                if r['route_domain'] > 0:
                    ns.write("tmsh create net route default_%s network default%%%s gw %s%%%s\n" % (
                        r['route_domain'], r['route_domain'], r['gateway'], r['route_domain']))
                else:
                    ns.write("tmsh create net route default network default gw %s%%%s\n" % (
                        r['gateway'], r['route_domain']))
            else:
                if 'netmask' in r:
                    ns.write("tmsh create net route %s_%s network %s%%%s/%s gw %s%%%s\n" % (
                        r['route_name'], r['route_domain'], r['network'], r['route_domain'], r['netmask'], r['gateway'], r['route_domain']))
                else:
                    rp = r['network'].slit('/')
                    ns.write("tmsh create net route %s_%s network %s%%%s/%s gw %s%%%s\n" % (
                        r['route_name'], r['route_domain'], rp[0], r['route_domain'], rp[1], r['gateway'], r['route_domain']))
    ds = []
    ts = []
    for service in nmd['services']:
        if service['type'] == 'dns' and (is_v6(service['address']) or is_v4(service['address']))::
            ds.append(service['address'])
        if service['type'] == 'ntp' and (is_v6(service['address']) or is_v4(service['address']))::
            ns.append(service['address'])
    with open('/config/services_setup.sh','w') as ss:
        if ds:
            ss.write("tmsh modify sys dns name-servers replace-all-with { %s }\n" % " ".join(ds))
        if not ts:
            ts.append("10.0.77.54")
        ss.write("tmsh modify sys ntp servers replace-all-with { %s }\n" % " ".join(ts))
