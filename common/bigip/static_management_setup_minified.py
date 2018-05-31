#!/bin/env python
import json, subprocess
nmd = json.load(open('/mnt/config/openstack/latest/network_data.json'))
for n in nmd['networks']:
 if n['link'] == nmd['links'][0]['id']:
  if (not n['type'] == 'ipv4_dhcp') and (not n['type'] == 'ipv6_dhcp'):
   mgmtaddr = "%s/%s" % (n['ip_address'], n['netmask'])
   subprocess.call(['/sbin/ip', 'addr', 'add', mgmtaddr, 'dev', 'mgmt'])
   subprocess.call(['/sbin/ip', 'link', 'set', 'mgmt', 'up'])

