#!/bin/bash

set -e

if [ $# -ne 9 ]; then
  echo "Usage: ./create-slave.sh <group_hash> <master_hostname> <slave_name> <slave_cpu> <slave_mem> <root_password> <network_id> <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY>"
  exit -1
fi

group_hash=$1
master=$2
slave_name=$3
slave_cpu=$4
slave_mem=$5
root_password=$6
network_id=$7
AWS_ACCESS_KEY_ID=$8
AWS_SECRET_ACCESS_KEY=$9

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

echo "Running create-server.sh"
echo "$DIR/create-server.sh $group_hash $slave_name $root_password $slave_cpu $slave_mem $network_id"
server_url=`$DIR/create-server.sh $group_hash $slave_name $root_password $slave_cpu $slave_mem $network_id`
echo "server_url: $server_url"

echo "Getting ip address..."
set +e
is_ip=0
while [ $is_ip == 0 ]; do
  echo "sleep 30"
  sleep 30
  echo "Running get-ip.sh"
  ip=`$DIR/get-ip.sh $server_url`
  echo "ip: $ip"
  if [[ $ip =~ ^\"[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\"$ ]]; then
    is_ip=1
    ip=${ip:1:${#ip}-2}
  fi 
done

echo "final ip: $ip"

set -e

echo "Adding pub key to authorized_keys on server"
python $DIR/add-auth-key.py $ip $root_password
echo "done"

echo "Copying provisioning scripts to $ip"
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -r $DIR root@$ip:
echo "done"

echo "Running set-hostnames.sh"
cmd="/root/provisioning/set-hostnames.sh"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$ip $cmd
echo "done"

echo "Running add-users.sh"
cmd="/root/provisioning/add-users.sh"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$ip $cmd
echo "done"

echo "Running install-hadoop.sh"
cmd="nohup /root/provisioning/install-hadoop.sh ${master} $slave_mem ${AWS_ACCESS_KEY_ID} ${AWS_SECRET_ACCESS_KEY} > install-hadoop.log 2>&1 < /dev/null &"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$ip $cmd
echo "done"
