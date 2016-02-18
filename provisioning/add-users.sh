#!/bin/bash
set -e

if [ $# -ne 0 ]; then
  echo "Usage: ./add-users.sh"
  exit -1
fi

echo "Configuring SSH for root...."
mkdir -p ~/.ssh
ssh-keygen -f ~/.ssh/id_rsa -t rsa -N ''
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

cat > ~/.ssh/config << EOL
Host *.*.*.*
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
Host localhost
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
EOL
echo "done"

echo "Enable sudo without password"
chmod 640 /etc/sudoers
echo "%wheel  ALL=(ALL)       NOPASSWD: ALL" >> /etc/sudoers
echo "done"

echo "Adding hadoop user..."
useradd hadoop
gpasswd -a hadoop wheel

echo "Configuring SSH for hadoop user...."
su - hadoop -c "ssh-keygen -f ~/.ssh/id_rsa -t rsa -N ''"
su - hadoop -c "cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys"
su - hadoop -c "cat /tmp/id_rsa.pub >> ~/.ssh/authorized_keys"
su - hadoop -c "chmod 644 ~/.ssh/authorized_keys"
su - hadoop -c "cat > ~/.ssh/config << EOL
Host *.*.*.*
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
Host localhost
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
EOL"
su - hadoop -c "chmod 644 ~/.ssh/config"
echo "done"
