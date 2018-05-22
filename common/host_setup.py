#!/bin/env python
import json, subprocess
md = json.load(open('/mnt/config/openstack/latest/meta_data.json'))
for k in md['public_keys']:
    with open('/root/.ssh/authorized_keys', 'a') as ak:
        ak.write(md['public_keys'][k] + '\n')
with open('/config/host_setup.sh', 'w') as hs:
    subprocess.call(['tmsh', 'modify', 'sys', 'global-settings', 'hostname', md['hostname']])
    subprocess.call(['tmsh', 'delete', 'cm', 'trust-domain', 'all'])
    subprocess.call(['tmsh', 'mv', 'cm', 'device', 'bigip1', md['hostname']])
    subprocess.call(['tmsh', 'modify', 'sys', 'global-settings', 'gui-setup', 'disabled'])
    subprocess.call(['touch', '/var/config/rest/iapps/enable'])
