#!/bin/bash
set -e

if [ $# -ne 4 ]; then
  echo "Usage: ./install-hadoop.sh <master_hostname> <slave_mem> <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY>"
  exit -1
fi

MASTER=$1
slave_mem=$2
AWS_ACCESS_KEY_ID=$3
AWS_SECRET_ACCESS_KEY=$4

yarn_mem=$[$slave_mem*1024*87/100]

my_hostname=`hostname`

mode="slave"
if [ "$MASTER" == "$my_hostname" ]; then
  mode="master"
fi

echo "MASTER: $MASTER"
echo "my_hostname: $my_hostname"
echo "mode: $mode"

# Try to install software using yum. For some reason first attempt might fail
echo "Installing JDK....."
set +e
yum -y install java-devel
if [ $? -ne 0 ]; then
  sleep 10
  set -e
  yum -y install java-devel
fi
set -e
echo "JDK Installation completed...."

echo "Installed java version is...."

java -version

javac -version

echo "Configuring SSH...."
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

useradd hadoop
gpasswd -a hadoop wheel

chmod 640 /etc/sudoers
echo "%wheel  ALL=(ALL)       NOPASSWD: ALL" >> /etc/sudoers

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

echo "Downloading Hadoop...."
cd /usr/lib
wget -q http://apache.mirrors.pair.com/hadoop/common/hadoop-2.7.1/hadoop-2.7.1.tar.gz
echo "Installing Hadoop...."
tar xzf hadoop-2.7.1.tar.gz
mv hadoop-2.7.1 hadoop
rm -rf hadoop-2.7.1.tar.gz

mkdir -p /hdfs/name
mkdir -p /hdfs/data
mkdir -p /var/log/hadoop-yarn/containers
mkdir -p /var/log/hadoop-yarn/apps
mkdir -p /var/log/hadoop /usr/lib/hadoop/logs
chown -R hadoop:hadoop /hdfs /var/log/hadoop-yarn /var/log/hadoop /usr/lib/hadoop/logs

echo "Configuring Hadoop...."

cd /usr/lib/hadoop/etc/hadoop

cat >> hadoop-env.sh << EOL
export JAVA_HOME=/usr/lib/jvm/java-openjdk
export HADOOP_LOG_DIR=/var/log/hadoop
if [ "\$HADOOP_CLASSPATH" ]; then
  export HADOOP_CLASSPATH=\$HADOOP_CLASSPATH:/usr/lib/hadoop/share/hadoop/tools/lib/*
else
  export HADOOP_CLASSPATH=/usr/lib/hadoop/share/hadoop/tools/lib/*
fi
EOL

cat >> mapred-env.sh << EOL
export HADOOP_MAPRED_LOG_DIR=/var/log/hadoop
EOL

cat >> yarn-env.sh << EOL
export YARN_LOG_DIR=/var/log/hadoop
EOL

cat > core-site.xml << EOL
<configuration>
  <property>
    <name>fs.default.name</name>
    <value>hdfs://${MASTER}:8020</value>
  </property>
  <property>
    <name>fs.s3.awsAccessKeyId</name>
    <value>${AWS_ACCESS_KEY_ID}</value>
  </property>
  <property>
    <name>fs.s3.awsSecretAccessKey</name>
    <value>${AWS_SECRET_ACCESS_KEY}</value>
  </property>
  <property>
    <name>fs.s3.impl</name>
    <value>org.apache.hadoop.fs.s3.S3FileSystem</value>
  </property>
  <property>
    <name>fs.s3n.awsAccessKeyId</name>
    <value>${AWS_ACCESS_KEY_ID}</value>
  </property>
  <property>
    <name>fs.s3n.awsSecretAccessKey</name>
    <value>${AWS_SECRET_ACCESS_KEY}</value>
  </property>
  <property>
    <name>fs.s3n.impl</name>
    <value>org.apache.hadoop.fs.s3native.NativeS3FileSystem</value>
  </property>
</configuration>
EOL

cat > mapred-site.xml << EOL
<configuration>
  <property>
    <name>mapreduce.framework.name</name>
    <value>yarn</value>
  </property>
  <property>
    <name>mapreduce.jobhistory.address</name>
    <value>${MASTER}:10020</value>
  </property>
  <property>
    <name>mapreduce.jobhistory.webapp.address</name>
    <value>${MASTER}:19888</value>
  </property>
  <property>
    <name>mapred.output.direct.EmrFileSystem</name>
    <value>true</value>
  </property>
  <property>
    <name>mapred.output.direct.NativeS3FileSystem</name>
    <value>true</value>
  </property>
  <property>
    <name>mapred.output.committer.class</name>
    <value>org.apache.hadoop.mapred.DirectFileOutputCommitter</value>
  </property>
</configuration>
EOL

cat > yarn-site.xml << EOL
<configuration>
  <property>
    <name>yarn.resourcemanager.hostname</name>
    <value>${MASTER}</value>
  </property>
  <property>
    <name>yarn.nodemanager.aux-services</name>
    <value>mapreduce_shuffle,spark_shuffle</value>
  </property>

  <property>
    <name>yarn.nodemanager.aux-services.spark_shuffle.class</name>
    <value>org.apache.spark.network.yarn.YarnShuffleService</value>
  </property>

  <property>
    <name>yarn.log-aggregation-enable</name>
    <value>true</value>
  </property>

  <property>
    <name>yarn.log.server.url</name>
    <value>http://${MASTER}:19888/jobhistory/logs</value>
  </property>

  <property>
    <description>Where to store container logs.</description>
    <name>yarn.nodemanager.log-dirs</name>
    <value>/var/log/hadoop-yarn/containers</value>
  </property>

  <property>
    <description>Where to aggregate logs to.</description>
    <name>yarn.nodemanager.remote-app-log-dir</name>
    <value>/var/log/hadoop-yarn/apps</value>
  </property>

  <property>
    <name>yarn.scheduler.minimum-allocation-mb</name>
    <value>1</value>
  </property>

  <property>
    <name>yarn.scheduler.maximum-allocation-mb</name>
    <value>${yarn_mem}</value>
  </property>

  <property>
    <name>yarn.nodemanager.resource.memory-mb</name>
    <value>${yarn_mem}</value>
  </property>

</configuration>
EOL

cat > hdfs-site.xml << EOL
<configuration>
  <property>
    <name>dfs.replication</name>
    <value>1</value>
  </property>
  <property>
    <name>dfs.namenode.name.dir</name>
    <value>file:///hdfs/name</value>
  </property>
  <property>
    <name>dfs.datanode.data.dir</name>
    <value>file:///hdfs/data</value>
  </property>
</configuration>
EOL

cat > jets3t.properties << EOL
s3service.s3-endpoint=canada.os.ctl.io
s3service.https-only=false
EOL

cat >> ~/.bashrc << EOL
export HADOOP_HOME=/usr/lib/hadoop
export HADOOP_CONF_DIR=/usr/lib/hadoop/etc/hadoop
export PATH=\$PATH:/usr/lib/hadoop/bin
EOL

mkdir /usr/lib/hadoop-s3
cp -n /usr/lib/hadoop/share/hadoop/tools/lib/*aws* /usr/lib/hadoop/share/hadoop/tools/lib/jets3t*.jar /usr/lib/hadoop/share/hadoop/common/lib/
cp -n /usr/lib/hadoop/share/hadoop/tools/lib/*aws* /usr/lib/hadoop/share/hadoop/tools/lib/jets3t*.jar /usr/lib/hadoop/share/hadoop/yarn/lib/
cp -n /usr/lib/hadoop/share/hadoop/tools/lib/*aws* /usr/lib/hadoop/share/hadoop/tools/lib/jets3t*.jar /usr/lib/hadoop-s3/

# Spark shuffle service jar
wget -q http://www.noetl.io/spark-1.6.0-yarn-shuffle.jar -P /usr/lib/hadoop/share/hadoop/yarn/lib

echo "Stop and disable firewall"
systemctl stop firewalld
systemctl disable firewalld

if [ "$mode" == "master" ]; then
  echo "Formatting HDFS...."
  su - hadoop -c '/usr/lib/hadoop/bin/hdfs namenode -format'
  echo "Formatting HDFS done"

  echo "Starting namenode...."
  su - hadoop -c '/usr/lib/hadoop/sbin/hadoop-daemons.sh \
    --config /usr/lib/hadoop/etc/hadoop \
    --script /usr/lib/hadoop/bin/hdfs start namenode'
  echo "Starting namenode done"

  echo "Starting YARN resourcemanager...."
  su - hadoop -c '/usr/lib/hadoop/sbin/yarn-daemon.sh --config /usr/lib/hadoop/etc/hadoop start resourcemanager'
  echo "Starting YARN resourcemanager done"

  echo "Starting JobHistory server...."
  su - hadoop -c '/usr/lib/hadoop/sbin/mr-jobhistory-daemon.sh --config /usr/lib/hadoop/etc/hadoop start historyserver'
  echo "Starting JobHistory server done"
else
  echo "Starting datanode...."
  su - hadoop -c '/usr/lib/hadoop/sbin/hadoop-daemons.sh \
    --config /usr/lib/hadoop/etc/hadoop \
    --script /usr/lib/hadoop/bin/hdfs start datanode'
  echo "Starting datanode done"

  echo "Starting YARN nodemanager...."
  su - hadoop -c '/usr/lib/hadoop/sbin/yarn-daemon.sh --config /usr/lib/hadoop/etc/hadoop start nodemanager'
  echo "Starting YARN nodemanager done"
fi

su - hadoop -c 'cat >> ~/.bashrc << EOL
export HADOOP_HOME=/usr/lib/hadoop
export HADOOP_CONF_DIR=/usr/lib/hadoop/etc/hadoop
export PATH=\$PATH:/usr/lib/hadoop/bin
EOL'

# echo "Testing MR..."
# /usr/lib/hadoop/bin/hadoop jar /usr/lib/hadoop/share/hadoop/mapreduce/hadoop-mapreduce-examples-2.7.1.jar pi 10 1000
