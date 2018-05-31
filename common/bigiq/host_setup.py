#!/bin/env python

import json
import os
import requests
import socket
import subprocess
import time
import yaml


def main():
 personality='big_iq'
 masterkey='BigIQ8675309!Jenny'

 (m_ip, m_nm, m_gw, m_mtu, s_ip, s_nm, s_gw, hostname, vlan, interface, ds, ts) = populate_from_metadata()
 (admin_password, root_password, tmos_basekey, as3_url, timezone) = populate_from_userdata()
 set_personality('admin', personality)
 host_setup('admin', hostname, m_ip, m_nm, m_gw, s_ip, s_nm, s_gw, vlan, interface)
 set_management_mtu(m_mtu)
 set_dns('admin', ds)
 set_ntp('admin', ts, timezone)
 set_masterkey('admin', masterkey)
 if tmos_basekey:
  activate_license('admin', tmos_basekey)
 if as3_url:
  install_as3(as3_url)
 set_root_password('admin', 'default', root_password)
 set_admin_password('admin', 'admin', admin_password)
 set_setupcomplete(admin_password)


def populate_from_metadata():

 m_ip=None
 m_nm=None
 m_gw=None
 m_mtu=None
 s_ip=None
 s_nm=None
 s_gw=None
 hostname=None
 vlan='internal'
 interface='1.1'
 ds = []
 ts = []

 nmd=json.load(open('/mnt/config/openstack/latest/network_data.json'))
 md=json.load(open('/mnt/config/openstack/latest/meta_data.json'))
 hostname=md['hostname']

 for k in md['public_keys']:
  with open('/root/.ssh/authorized_keys','a')as ak:
   ak.write(md['public_keys'][k]+'\n')

 if nmd['networks'][0]['type']=='ipv4_dhcp' or nmd['networks'][0]['type']=='ipv6_dhcp':
  m_ip=subprocess.Popen("egrep -m 1 -A 1 eth0 /var/lib/dhclient/dhclient.leases | grep fixed-address | cut -d' ' -f4 | tr -d ';\n'",stdout=subprocess.PIPE,shell=True).communicate()[0]
  m_nm=subprocess.Popen("egrep -m 1 -A 2 eth0 /var/lib/dhclient/dhclient.leases | grep subnet-mask | cut -d' ' -f5 | tr -d ';\n'",stdout=subprocess.PIPE,shell=True).communicate()[0]
  m_gw=subprocess.Popen("egrep -m 1 -A 4 eth0 /var/lib/dhclient/dhclient.leases | grep routers | cut -d' ' -f5 | tr -d ';\n'",stdout=subprocess.PIPE,shell=True).communicate()[0]
  m_mtu=subprocess.Popen("egrep -m 1 -A 9 eth0 /var/lib/dhclient/dhclient.leases | grep interface-mtu | cut -d' ' -f5 | tr -d ';\n'",stdout=subprocess.PIPE,shell=True).communicate()[0]
 else:
  m_ip=nmd['networks'][0]['ip_address']
  m_nm=nmd['networks'][0]['netmask']
  for r in nmd['networks'][0]['routes']:
   if r['network']=='0.0.0.0' or r['network']=='::':
    m_gw=r['gateway']
    m_mtu=nmd['links'][0]['mtu']
   if nmd['networks'][1]['type']=='ipv4_dhcp' or nmd['networks'][1]['type']=='ipv6_dhcp':
    print('DHCP not supported on BIG-IQ internal VLAN')
   else:
    s_ip=nmd['networks'][1]['ip_address']
    s_nm=nmd['networks'][1]['netmask']
    for r in nmd['networks'][1]['routes']:
     if r['network']=='0.0.0.0' or r['network']=='::':
      s_gw=r['gateway']

 for service in nmd['services']:
  if service['type']=='dns' and (is_v6(service['address']) or is_v4(service['address'])):
   ds.append(service['address'])
  if service['type']=='ntp' and (is_v6(service['address']) or is_v4(service['address'])):
   ns.append(service['address'])

 return (m_ip, m_nm, m_gw, m_mtu, s_ip, s_nm, s_gw, hostname, vlan, interface, ds, ts)


def populate_from_userdata():

 admin_password = 'ibmsoftlayer'
 root_password = 'ibmsoftlayer'
 tmos_basekey = None
 as3_url = None
 timezone = 'America/Chicago'

 if os.path.exists('/mnt/config/openstack/latest/user_data'):
  try:
   ud = yaml.load(open('/mnt/config/openstack/latest/user_data'))
   if 'password' in ud:
    admin_password = ud['password']
    root_password = ud['password']
   if 'tmos_basekey' in ud:
    tmos_basekey = ud['tmos_basekey']
   if 'as3_url' in ud:
    as3_url = ud['as3_url']
   if 'timezone' in ud:
    timezone = ud['timezone']
  except Exception:
   pass
  return (admin_password, root_password, tmos_basekey, as3_url, timezone)


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


def get_bigiq_session(username=None, password=None):
 if not username:
  username='admin'
 if not password:
  password='admin'
 bigiq = requests.Session()
 bigiq.verify = False
 bigiq.headers.update({'Content-Type': 'application/json'})
 bigiq.timeout = 10
 data = {'username': username, 'password': password, 'loginProviderName':'local'}
 while True:
  try:
   repsonse = bigiq.post('https://localhost/mgmt/shared/authn/login',
                         data=json.dumps(data),
                         auth=requests.auth.HTTPBasicAuth(username, password))
   response_json = repsonse.json()
   bigiq.headers.update({'X-F5-Auth-Token': response_json['token']['token']})
   return bigiq
  except Exception:
   time.sleep(2)


def activate_license(admin_password, basekey):
 bigiq = get_bigiq_session(username='admin', password=admin_password)
 response = bigiq.post('https://loclhost/mgmt/tm/shared/licensing/activation',
                       data="{'baseRegKey':'%s'}" % baskey)
 if response.status_code > 399:
  print("Error activating license %s: %s" % (response.status_code, response.text))


def set_personality(admin_password, personality):
 bigiq = get_bigiq_session(username='admin', password=admin_password)
 response = bigiq.post('https://localhost/mgmt/cm/system/provisioning',
            data="{'systemPersonality':'%s'}" % personality)
 if response.status_code > 399:
  print("Error setting device personality %s: %s" % (response.status_code, response.text))


def host_setup(admin_password, hostname, m_ip, m_nm, m_gw, s_ip, s_nm, s_gw, vlan, interface):
 bigiq = get_bigiq_session(username='admin', password=admin_password)
 data = {}
 data['hostname'] = hostname
 if is_v4(m_ip):
     if len(m_nm) > 3:
         m_nm = sum([bin(int(x)).count('1') for x in m_nm.split('.')])
 data['managementIpAddress'] = "%s/%s" % (m_ip, m_nm)
 data['managementRouteAddress'] = m_gw
 data['selfIpAddresses'] = []
 address = {}
 if is_v4(s_ip):
     if len(s_nm) > 3:
         s_nm = sum([bin(int(x)).count('1') for x in s_nm.split('.')])
 address['address'] = "%s/%s" % (s_ip, s_nm)
 address['vlan'] = 'internal'
 address['iface'] = '1.1'
 data['selfIpAddresses'].append(address)
 response = bigiq.patch('https://localhost/mgmt/shared/system/easy-setup',
                        data=json.dumps(data))
 if response.status_code > 399:
  print("Error setting up host %s: %s" % (response.status_code, response.text))


def set_management_mtu(m_mtu):
 subprocess.call(['ip', 'link', 'set', 'mtu', m_mtu, 'eth0'])
 with open('/config/startup','w') as startup:
  startup.write("ip link set mtu %s eth0\n" % m_mtu) 


def set_dns(admin_password, dnsservers):
 if dnsservers:
  bigiq = get_bigiq_session(username='admin', password=admin_password)
  nameServers = {'nameServers': dnsservers, 'search':['localhost']}
  response = bigiq.patch('https://localhost/mgmt/tm/sys/dns', data=json.dumps(nameServers))
  if response.status_code > 399:
   print("Error setting DNS %s: %s" % (response.status_code, response.text))


def set_ntp(admin_password, ntpservers, timezone):
 if ntpservers:
  bigiq = get_bigiq_session(username='admin', password=admin_password)
  ntpServers = {'servers': ntpservers, 'timezone':timezone}
  response = bigiq.patch('https://localhost/mgmt/tm/sys/ntp', data=json.dumps(ntpServers))
  if response.status_code > 399:
   print("Error setting NTP %s: %s" % (response.status_code, response.text))


def set_masterkey(admin_password, masterkey):
 if masterkey:
  bigiq = get_bigiq_session(username='admin', password=admin_password)
  response = bigiq.post('https://localhost/mgmt/cm/shared/secure-storage/masterkey',
                       data="{'passphrase':'%s'}" % masterkey)
  if response.status_code > 399:
   print("Error setting device masterkey %s: %s" % (response.status_code, response.text))


def set_root_password(admin_password, oldpassword, newpassword):
 bigiq = get_bigiq_session(username='admin', password=admin_password)
 response = bigiq.post('https://localhost/mgmt/shared/authn/root',
                       data="{'oldPassword':'%s', 'newPassword':'%s'}" % (oldpassword, newpassword))
 if response.status_code > 399:
  print("Error setting root password %s: %s" % (response.status_code, response.text))
 response = bigiq.patch('https://localhost/mgmt/shared/system/setup',
                        data="{'isRootPasswordChanged':true}")
 if response.status_code > 399:
  print("Error setting root password changed %s: %s" % (response.status_code, response.text))


def set_admin_password(admin_password, oldpassword, newpassword):
 bigiq = get_bigiq_session(username='admin', password=admin_password)
 response = bigiq.get('https://localhost/mgmt/shared/authz/users/admin')
 data = response.json()
 data['generation'] = (int(data['generation']) + 1)
 data['lastUpdateMicros'] = (int(data['lastUpdateMicros']) + 100)
 data['oldPassword'] = oldpassword
 data['password'] = newpassword
 data['password2'] = newpassword
 data['encryptPassword'] = 'null'
 response = bigiq.put('https://localhost/mgmt/shared/authz/users',
                      data=json.dumps(data))
 if response.status_code > 399:
  print("Error setting admin password %s: %s" % (response.status_code, response.text))
 reponse = bigiq.patch('https://localhost/mgmt/shared/system/setup',
                       data="{'isAdminPasswordChanged':true}")
 if response.status_code > 399:
  print("Error setting admin password changed %s: %s" % (response.status_code, response.text))


def set_setupcomplete(admin_password):
 bigiq = get_bigiq_session(username='admin', password=admin_password)
 response = bigiq.post('https://localhost/mgmt/shared/system/setup',
                       data="{'isSystemSetup':true}")
 if response.status_code > 399:
  print("Error setting setup completequit %s: %s" % (response.status_code, response.text))


def install_as3(as3_url):
    try:
        subprocess.call(['rpm', '-i', as3_url])
    except Exception as exc:
        print("Error installing AS3: %s" % str(exc))


if __name__ == "__main__":
    main()
