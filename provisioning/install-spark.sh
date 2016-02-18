#!/bin/bash
set -e

if [ $# -ne 2 ]; then
  echo "Usage: ./install-spark.sh <N_of_boxes> <slave_mem>"
  exit -1
fi

N=$1
slave_mem=$2

# give 50% of cluster resources to Spark
exec_inst=$[$N/2]

yarn_mem=$[$slave_mem*1024*87/100]
spark_mem=$[yarn_mem-896]
exec_mem=$[$spark_mem*10/11]

MASTER=`hostname`

echo "MASTER: $MASTER"

echo "Downloading Spark...."
cd /usr/lib
wget -q http://download.nextag.com/apache/spark/spark-1.6.0/spark-1.6.0-bin-hadoop2.6.tgz
echo "Installing Spark...."
tar zxf spark-1.6.0-bin-hadoop2.6.tgz
mv spark-1.6.0-bin-hadoop2.6 spark
rm -rf spark-1.6.0-bin-hadoop2.6.tgz

mkdir -p /var/log/spark
chown hadoop:hadoop /var/log/spark

su - hadoop -c '/usr/lib/hadoop/bin/hadoop fs -mkdir -p /var/log/spark/apps'
su - hadoop -c '/usr/lib/hadoop/bin/hadoop fs -chmod g+w /var/log/spark/apps'

echo "Configuring Spark...."

cd /usr/lib/spark/conf

cat > spark-env.sh << EOL
export SPARK_HOME=${SPARK_HOME:-/usr/lib/spark}
export SPARK_LOG_DIR=${SPARK_LOG_DIR:-/var/log/spark}
export HADOOP_HOME=${HADOOP_HOME:-/usr/lib/hadoop}
export HADOOP_CONF_DIR=${HADOOP_CONF_DIR:-/usr/lib/hadoop/etc/hadoop}
export HIVE_CONF_DIR=${HIVE_CONF_DIR:-/usr/lib/hive/conf}
EOL

cat > spark-defaults.conf << EOL
spark.master yarn
spark.eventLog.enabled true
spark.eventLog.dir hdfs:///var/log/spark/apps
spark.history.fs.logDirectory hdfs:///var/log/spark/apps
spark.yarn.historyServer.address ${MASTER}:18080
spark.history.ui.port 18080
spark.shuffle.service.enabled true
spark.driver.extraJavaOptions    -Dfile.encoding=UTF-8
spark.executor.extraJavaOptions  -Dfile.encoding=UTF-8
spark.driver.extraClassPath     /usr/lib/hadoop/etc/hadoop:/usr/lib/hadoop-s3/*
spark.executor.extraClassPath   /usr/lib/hadoop/etc/hadoop:/usr/lib/hadoop-s3/*
spark.executor.instances    ${exec_inst}
spark.executor.memory       ${exec_mem}m
EOL

echo "Configuring Spark done"

cat >> ~/.bashrc << EOL
export SPARK_CONF_DIR=/usr/lib/spark/conf
export PATH=\$PATH:/usr/lib/spark/bin
EOL

echo "Starting spark history server...."
su - hadoop -c '/usr/lib/spark/sbin/start-history-server.sh'
echo "Starting spark history server done"
