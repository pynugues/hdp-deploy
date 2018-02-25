# hdp-deploy
hdp-deploy is a bash script that will install a full single node HDP cluster using Ambari. The aim is that hdp-deploy will always install the latest version of HDP and Ambari which is currently available for download from the [Hortonworks website](https://hortonworks.com/downloads/)

### Usage
The general gist to use hdp-deploy:
```
yum -y install git
git clone https://github.com/willie-engelbrecht/hdp-deploy.git
./hdp-deploy/hdp-deploy.sh
```

By default hdp-deploy will setup and download repositories from directly from the internet. However it is also possible to use hdp-deply in an "offline" mode, by editing the repo.env file and changing the value to 0 for:
```
USE_LOCAL_REPO=0
```

And then updating the local repo locations:
```
export AMBARI=http://192.168.1.105/hwx/ambari-latest/
export HDP=http://192.168.1.105/hwx/HDP-latest/
export HDPUTILS=http://192.168.1.105/hwx/HDP-UTILS-latest/
export HDPGPL=http://192.168.1.105/hwx/HDP-GPL/
```

When hdp-deploy is finished, it will print the following to screen, as well as save it to /root/ambari_install.txt
```
###########################################################
# YOUR CLUSTER IS NOW READY!
# Ambari: http://192.168.1.11:8080
# username: admin    password: 4d4a6e1a7e
# username: willie   password: 4d4a6e1a7e
#
# KDC REALM: HWX.COM
# principal: admin/admin@HWX.COM
# password:  hadoop
#
# Username/Password info stored in /root/ambari_install.txt
###########################################################
```

### Components
hdp-deploy will fully install the following components:
  * HDFS
  * Yarn
  * MapReduce
  * Tez
  * Hive (MySQL database)
  * HBase
  * Pig
  * Sqoop
  * Zookeper
  * Ambari Infra
  * Ambari Metrics
  * Atlas
  * Kafka
  * Ranger
  * SmartSense
  * Spark2
  * Driud
  * Superset
  
Over and above, hdp-deploy will also:
  * Create an Ambari user called willie (random password)
  * Linux system user called willie (random password)
  * Update Ambari admin to a random password
  * Download an example "employees" database, and import to MySQL
  * Sqoop the above employees database and tables from MySQL to Hive
  * Capture the Sqoop lineage and Hive tables in Atlas' metadata
  * Setup Atlas with a PII tag, and associate it with the "employees" Hive table
  * Setup Ranger Tags, and create a single tag policy for PII 
  * Allow the user willie access to the PII tag in Ranger Tag policy
  * Create a new Ranger HDFS policy for the directory /test, allowing willie access to this directory
  * Create a new group in Ranger called DataEngineers, and add user willie to this group
  * Enable time-based policies in Ranger, allowing you to specify during which time a policy is allowed/denied. Eg: 8am-5pm
  * Setup Ranger SOLR audits in Ambari Infra 
  * Setup a KDC (@HWX.COM), which you can use Kerberise your cluster if you so wish  
