import os
import paramiko
import sys

server_ip=sys.argv[1]
passw=sys.argv[2]

home=os.path.expanduser('~')
with open(home + "/.ssh/id_rsa.pub") as f:
    content = f.readlines()

pub_key=content[0]
#paramiko.util.log_to_file('ssh.log') # sets up logging

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(server_ip, username='root', password=passw)

stdin1, stdout1, stderr1 = client.exec_command('mkdir -p /root/.ssh')
stdout1.read()
cmd2='echo "' + pub_key + '" >> /root/.ssh/authorized_keys'
stdin2, stdout2, stderr2 = client.exec_command(cmd2)
stdout2.read()

cmd3='echo "' + pub_key + '" > /tmp/id_rsa.pub'
stdin3, stdout3, stderr3 = client.exec_command(cmd3)
stdout3.read()

client.close()
