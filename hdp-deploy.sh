# Check that we "in" our directory
ls -l singlenode.ranger.blueprint > /dev/null 2> /dev/null
if [ $? -ne 0 ]
then
    #echo "###############################################################################"
    #echo "# ERROR:                                                                      #"
    #echo "# Please first \"cd\" to the directory of hdpdeploy, and then run the install   #"
    #echo "###############################################################################"
    #echo ""
    #exit 1;
    cd $(dirname $(pwd)/$0)
fi

# Setup some variables 
source repo.env
export HDP_VERSION_SHORT="3.1"
export HDP_VERSION_LONG=$(echo "${REPODEV}" | sed 's/HDP-\|.xml//g')
export UTILS_VERSION="1.1.0.22"

export REALM=HWX.COM
export OS="redhat7"
export CLUSTER_NAME="singlenode"
export FQDNx="$(hostname -f)" # There will be an annoying space added to the end. Next command will clear it with xargs
export FQDN=$(echo $FQDNx | xargs)
#export FQDN=$(hostname -f)

# Check if the paywall username/password has values, otherwise quit the script
if [ -z "${PWALL_USER}" ]; 
then
    echo "Please set a valid username for your PWALL_USER in repo.env"
    echo "Exiting..."
    exit 1
fi
if [ -z "${PWALL_PASS}" ]; 
then
    echo "Please set a valid password for your PWALL_PASS in repo.env"
    echo "Exiting..."
    exit 1
fi

# Local stuff 
rm -f /etc/yum.repos.d/local-hwx.repo

# Set TimeZone
ln -sf /usr/share/zoneinfo/${LOCALTZ} /etc/localtime

# Disable auditd
systemctl disable auditd

# Set long timeout for hung tasks
echo "kernel.hung_task_timeout_secs=999999999" >> /etc/sysctl.d/99-sysctl.conf
sysctl -p

# Find out if we are running on a specific cloud provider
yum -y install dmidecode curl
dmidecode | grep -i 'Asset Tag: Amazon EC2'
if [ $? -eq 0 ] # we are on AWS
then
#    FQDN=$(curl -s http://169.254.169.254/latest/meta-data/public-hostname)
    export FQDN=$(curl -s ipinfo.io/hostname)
    if [ $? -ne 0 ]
    then
        export FQDN=$(curl -s ipinfo.io/ip)
    fi
fi

# Check that we are running on CentOS7
cat /etc/os-release | grep VERSION_ID | grep 7 > /dev/null;
if [ $? -ne 0 ]
then
    echo "This system must be a CentOS7/RHEL7 based installation."
    echo ""
    echo "Suggested cloud image names:"
    echo "AWS: ami-ee6a718a "
    echo ""
    echo "Quitting...."
    exit 1;
fi

# Check that we are root user
whoami | grep root > /dev/null
if [ $? -ne 0 ]
then
    echo "You need to run this script as the root user, or with sudo."
    echo ""
    echo "Quitting...."
    exit 1;
fi

# Generate a 10 char random password
RAND_STRING="a$(echo "$(date)$(hostname)" | md5sum);"
RAND_PW=$(echo ${RAND_STRING:0:10})

# Setup the Ambari repository
yum -y install wget

if [ "${USE_LOCAL_REPO}" == "0" ]
then
   wget -q -O - ${AMBARI_UPSTREAM} > /etc/yum.repos.d/ambari.repo 
   
   # Add in the Paywall Username & Password into the repo strings
   sed -i "s/archive/${PWALL_USER}:${PWALL_PASS}@archive/g" /etc/yum.repos.d/ambari.repo
fi

if [ "${USE_LOCAL_REPO}" == "1" ]
then
    cat > /etc/yum.repos.d/local-ambari.repo << EOF
[LocalAmbari]
name=Local Ambari Repo
baseurl=$AMBARI
enabled=1
gpgcheck=0
EOF
fi

# Download the VDH file
wget -q -O - ${VDF_UPSTREAM} > /tmp/${REPODEV}

# Download the GPG key
wget -q -O - ${GPG_KEY} > /root/HDP-GPG-KEY

# Import HDP GPG key
rpm --import /root/HDP-GPG-KEY

# Install required packages
yum -y install yum-utils deltarpm
yum-complete-transaction --cleanup-only
yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
#yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

yum --nogpgcheck -y install java-1.8.0-openjdk-devel ambari-agent ambari-server mariadb-server mariadb mysql-connector-java mlocate telnet krb5-server krb5-libs krb5-workstation at jq libtirpc-devel #postgresql10-server postgresql10 #docker-ce container-selinux

rpm -qa | grep libtirpc-devel
if [ $? -ne 0 ]
then
    yum -y install  http://mirror.centos.org/centos/7/os/x86_64/Packages/libtirpc-devel-0.2.4-0.15.el7.x86_64.rpm
fi

sleep 2;
systemctl enable atd
systemctl start atd


## Initialize Postgresql
#/usr/pgsql-10/bin/postgresql-10-setup initdb
#/usr/pgsql-9.6/bin/postgresql96-setup initdb

# Setup the pg_hba.conf file
#cat > /var/lib/pgsql/9.6/data/pg_hba.conf << EOF
#cat > /var/lib/pgsql/10/data/pg_hba.conf << EOF
#  # TYPE  DATABASE        USER            ADDRESS                 METHOD
#  local   all             all                                     peer
#  host    ambari          ambari          0.0.0.0/0               md5
#  host    das             das             0.0.0.0/0               md5
#EOF

# Listen on all interfaces
#sed -e 's,#listen_addresses = \x27localhost\x27,listen_addresses = \x27*\x27,g' -i /var/lib/pgsql/10/data/postgresql.conf
#sed -e 's,#listen_addresses = \x27localhost\x27,listen_addresses = \x27*\x27,g' -i /var/lib/pgsql/9.6/data/postgresql.conf

## Start Postgres service and config it for restart on reboot
#systemctl enable postgresql-10
#systemctl start postgresql-10
#systemctl enable postgresql-9.6
#systemctl start postgresql-9.6

# Create a DDL file for all our DBs
#cat > /tmp/create_ddl.sql << EOF
#CREATE ROLE das LOGIN PASSWORD 'supersecret1';
#CREATE ROLE ambari LOGIN PASSWORD 'supersecret1';
#CREATE ROLE mapred LOGIN PASSWORD 'supersecret1';
#CREATE DATABASE das OWNER das ENCODING 'UTF-8';
#CREATE DATABASE ambari OWNER ambari ENCODING 'UTF-8';
#EOF

# Load the new users roles into Postgres
#sudo -u postgres psql < /tmp/create_ddl.sql
#su - postgres -c 'psql < /tmp/create_ddl.sql'
#su - postgres -c 'psql ambari < /var/lib/ambari-server/resources/Ambari-DDL-Postgres-CREATE.sql'

#cat > /tmp/create_grants.sql << EOF
#GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ambari;
#EOF
#su - postgres -c 'psql ambari < /tmp/create_grants.sql'

#systemctl enable docker
#systemctl start docker

adduser willie
echo ${RAND_PW} | passwd --stdin willie

# Setup a local KDC (HWX.COM)
# See: https://community.hortonworks.com/articles/29203/automated-kerberos-installation-and-configuration.html
# Git repo: git clone https://github.com/crazyadmins/useful-scripts.git
printf "\nConfiguring Kerberos:\n"
cat /etc/krb5.conf > /root/krb5.conf.back
cat /etc/krb5.conf > /root/krb5.conf.default
sed -i "s/EXAMPLE.COM/$REALM/g" /root/krb5.conf.default
sed -i "s/kerberos.example.com/$FQDN/g" /root/krb5.conf.default
sed -i 's/# default_realm = HWX.COM/ default_realm = HWX.COM/' /root/krb5.conf.default
sed -i 's/# HWX.COM/  HWX.COM/' /root/krb5.conf.default
sed -i 's/#  kdc/   kdc/' /root/krb5.conf.default
sed -i 's/#  admin_server/   admin_server/' /root/krb5.conf.default
sed -i 's/# }/}/' /root/krb5.conf.default
cat /root/krb5.conf.default > /etc/krb5.conf
kdb5_util create -s -P hadoop

printf "\nStarting KDC services:\n"
systemctl enable krb5kdc
systemctl enable kadmin
systemctl start krb5kdc
systemctl start kadmin

printf "\nCreating admin principal:\n"
kadmin.local -q "addprinc -pw hadoop admin/admin"
sed -i "s/EXAMPLE.COM/$REALM/g" /var/kerberos/krb5kdc/kadm5.acl
sed -i "s/EXAMPLE.COM/$REALM/g" /var/kerberos/krb5kdc/kdc.conf

printf "\nRestarting kadmin:\n"
systemctl restart krb5kdc
systemctl restart kadmin

# Setup the ambari-agent
# Setup a script to change the public IP used to report to Ambari
printf "\nConfiguring ambari-agent:\n"
sed -i 's/\[agent\]/\[agent\]\npublic_hostname_script=\/var\/lib\/ambari-agent\/public_hostname.sh/' /etc/ambari-agent/conf/ambari-agent.ini 
cat > /var/lib/ambari-agent/public_hostname.sh << EOF
#!/bin/sh
echo '$FQDN'
EOF
chmod 775 /var/lib/ambari-agent/public_hostname.sh
# See: https://community.hortonworks.com/articles/188269/javapython-updates-and-ambari-agent-tls-settings.html
sed -i '53i force_https_protocol=PROTOCOL_TLSv1_2' /etc/ambari-agent/conf/ambari-agent.ini
systemctl enable ambari-agent
service ambari-agent restart

# Setup the ambari-server
printf "\nConfiguring ambari-server:\n"
systemctl enable ambari-server
#ambari-server setup --enable-lzo-under-gpl-license -j /usr/lib/jvm/java-1.8.0-openjdk -s --database=postgres --databasehost=localhost --databaseport=5432 --databasename=ambari --databaseusername=ambari --databasepassword=supersecret1
ambari-server setup --enable-lzo-under-gpl-license -j /usr/lib/jvm/java-1.8.0-openjdk -s 

# Download the DAS LITE Mpack and add to Ambari
wget -q -O - ${DAS_LITE} > /tmp/DAS-lite.tar.gz
ambari-server install-mpack --mpack=/tmp/DAS-lite.tar.gz --force

# Start and configure Ambari
ambari-server start
printf "\nRunning ambari-server setup...\n"
ambari-server setup --jdbc-db=mysql --jdbc-driver="/usr/share/java/mysql-connector-java.jar"
yum -y remove pgdg-redhat-repo-42.0-5.noarch

# Make MySQL listen on localhost only
printf "\nConfiguring MySQL/MariaDB:\n"
sed -i '/\[mysqld\]/a bind-address = 127.0.0.1' /etc/my.cnf
# Setup the MySQL for Hive/Ranger
systemctl enable mariadb
systemctl start mariadb
/usr/bin/mysqladmin -u root password 'admin'

mysql -u root -padmin << EOF
create database hive;
create database ranger;
create database registry;
create database streamline;
create database superset;
create database druid character set utf8 collate utf8_general_ci;
create database rangerkms;
create database streamsmsgmgr;

create user 'hive'@'%' identified by 'hive';
create user 'rangeradmin'@'%' identified by 'rangeradmin';

grant all privileges on hive.* to 'hive'@'%' with grant option;
grant all privileges on ranger.* to 'rangeradmin'@'%' with grant option;

create user 'hive'@'localhost' identified by 'hive';
create user 'rangeradmin'@'localhost' identified by 'rangeradmin';

grant all privileges on hive.* to 'hive'@'localhost' with grant option;
grant all privileges on ranger.* to 'rangeradmin'@'localhost' with grant option;

create user 'registry'@'localhost' identified by 'registry';
create user 'registry'@'%' identified by 'registry';

grant all privileges on registry.* to 'registry'@'localhost' with grant option;
grant all privileges on registry.* to 'registry'@'%' with grant option;

create user 'streamline'@'localhost' identified by 'streamline';
create user 'streamline'@'%' identified by 'streamline';

grant all privileges on streamline.* to 'streamline'@'localhost' with grant option;
grant all privileges on streamline.* to 'streamline'@'%' with grant option;

create user 'superset'@'localhost' identified by 'superset';
create user 'superset'@'%' identified by 'superset';

grant all privileges on superset.* to 'superset'@'localhost' with grant option;
grant all privileges on superset.* to 'superset'@'%' with grant option;

create user 'druid'@'localhost' identified by 'druid';
create user 'druid'@'%' identified by 'druid';

grant all privileges on druid.* to 'druid'@'localhost' with grant option;
grant all privileges on druid.* to 'druid'@'%' with grant option;

create user 'rangerkms'@'localhost' identified by 'rangerkms';
create user 'rangerkms'@'%' identified by 'rangerkms';

grant all privileges on rangerkms.* to 'rangerkms'@'localhost' with grant option;
grant all privileges on rangerkms.* to 'rangerkms'@'%' with grant option;

create user 'streamsmsgmgr'@'localhost' identified by 'streamsmsgmgr';
create user 'streamsmsgmgr'@'%' identified by 'streamsmsgmgr';

grant all privileges on streamsmsgmgr.* to 'streamsmsgmgr'@'localhost' with grant option;
grant all privileges on streamsmsgmgr.* to 'streamsmsgmgr'@'%' with grant option;

flush privileges;
EOF



# Setup hostmapping
cat > "/tmp/singlenode.hostmapping" << EOF
{
  "blueprint":"singlenode",
  "repository_version": "xxHDPVERSIONxx",
  "config_recommendation_strategy" : "ALWAYS_APPLY_DONT_OVERRIDE_CUSTOM_VALUES",
  "default_password":"admin",
  "host_groups":[
    {
      "name":"all",
      "hosts":[ { "fqdn":"`hostname -f`" } ]
    }
  ]
}
EOF
sed -i "s/xxHDPVERSIONxx/${HDP_VERSION_LONG}/" /tmp/singlenode.hostmapping

cat > "/tmp/singlenode.krb.hostmapping" << EOF
{
  "blueprint":"singlenode",
  "repository_version": "xxHDPVERSIONxx",
  "config_recommendation_strategy" : "ALWAYS_APPLY_DONT_OVERRIDE_CUSTOM_VALUES",
  "default_password":"admin",
  "host_groups":[
    {
      "name":"all",
      "hosts":[ { "fqdn":"`hostname -f`" } ]
    }
  ],
  "credentials" : [
     {
       "alias" : "kdc.admin.credential",
       "principal" : "${KDC_PRINC}",
       "key" : "${KDC_PASS}",
       "type" : "TEMPORARY"
     }
    ],
   "security" : {
        "type" : "${SECURITY_TYPE}"
   },
   "configurations": [
        ${SETTINGS}
       ]
}
EOF
sed -i "s/xxHDPVERSIONxx/${HDP_VERSION_LONG}/" /tmp/singlenode.krb.hostmapping

echo ""
echo "##################################################"
echo "# BASH VARIABLES:                                "
echo "# HDP_VERSION_SHORT=$HDP_VERSION_SHORT           "
echo "# HDP_VERSION_LONG=$HDP_VERSION_LONG             "
echo "# UTILS_VERSION=$UTILS_VERSION                   "
#echo "# HDF_VERSION=$HDF_VERSION                       "
#echo "# SOLR_VERSION=$SOLR_VERSION                     "
echo "# OS=$OS                                         "
echo "# CLUSTER_NAME=$CLUSTER_NAME                     "
echo "# FQDN=$FQDN                                     "
echo "##################################################"
sleep 2
echo ""

# Waiting for Ambari server to start
echo "Waiting for Ambari server at http://${FQDN}:8080 to respond to requests."
 while [ `curl -o /dev/null --silent --head --write-out '%{http_code}\n' http://${FQDN}:8080` != 200 ]; do
  echo -n .; sleep 2
done
echo ""

# Setup HDF Mpack 
#echo "Setup HDF Mpack:"
#ambari-server install-mpack --mpack=${HDFMPACK}

# Setup SOLR Mpack
#echo "Setup SOLR Mpack:"
#ambari-server install-mpack --mpack=${SOLRMPACK}

#ambari-server restart

# Waiting for Ambari server to start
#echo "Waiting for Ambari server at http://${FQDN}:8080 to respond to requests."
# while [ `curl -o /dev/null --silent --head --write-out '%{http_code}\n' http://${FQDN}:8080` != 200 ]; do
#  echo -n .; sleep 2
#done
#echo ""

##########################################################
# Load a new repo version definition
#cat ${REPODEV} > /tmp/${REPODEV}
if [ ${USE_LOCAL_REPO} -eq 0 ]
then
    # Update the repo with Paywall logins
    # Add in the Paywall Username & Password into the repo strings
    sed -i "s/archive/${PWALL_USER}:${PWALL_PASS}@archive/g" /tmp/${REPODEV}
    curl --user admin:admin -H "X-Requested-By:ambari" -X POST http://localhost:8080/api/v1/version_definitions -d "{\"VersionDefinition\": { \"version_url\": \"file:/tmp/${REPODEV}\" } }"
fi

if [ ${USE_LOCAL_REPO} -eq 1 ]
then
    # Replace the external repo locations with internal ones
#    sed -i "s;${HDP_UPSTREAM};${HDP};" /tmp/${REPODEV}
#    sed -i "s;${HDPUTILS_UPSTREAM};${HDPUTILS};" /tmp/${REPODEV}
#    sed -i "s;${HDPGPL_UPSTREAM};${HDPGPL};" /tmp/${REPODEV}
    
    sed -i "39s;.*;        <baseurl>${HDP}</baseurl>;" /tmp/${REPODEV}
    sed -i "45s;.*;        <baseurl>${HDPGPL}</baseurl>;" /tmp/${REPODEV}
    sed -i "54s;.*;        <baseurl>${HDPUTILS}</baseurl>;" /tmp/${REPODEV}

    curl --user admin:admin -H "X-Requested-By:ambari" -X POST http://localhost:8080/api/v1/version_definitions -d "{\"VersionDefinition\": { \"version_url\": \"file:/tmp/${REPODEV}\" } }"
    echo ""
fi


# Tell Ambari the blueprint of the cluster
sleep 1
echo ""
echo "Loading the Blueprint in Ambari:"
echo "PWD: `pwd`"
echo "whoami: `whoami`"
echo "FQDN: $FQDN"
echo "Random PW: $RAND_PW"
#set -x
sed  "s/xxFQDNxx/$FQDN/g" singlenode.ranger.blueprint > /tmp/singlenode.ranger.blueprint
sed  -i "s/xxxADMINPWxx/$RAND_PW/g" /tmp/singlenode.ranger.blueprint
curl --user admin:admin -H X-Requested-By:autohdp -X POST http://localhost:8080/api/v1/blueprints/$CLUSTER_NAME -d @/tmp/singlenode.ranger.blueprint

# Tell Ambari the hostmapping and this will also start the installation
sleep 1
echo ""
echo "Loading the Hostmapping and starting the install:"
curl --user admin:admin -H X-Requested-By:autohdp -X POST http://localhost:8080/api/v1/clusters/$CLUSTER_NAME -d @/tmp/singlenode.hostmapping

##########################################################


# Waiting for the HDP install to finish ....
echo ""
RET=-1
echo "Installation URL to monitor: http://${FQDN}:8080"
echo -n "Waiting for the HDP install to finish ...."
until [ ${RET} -eq 0 ]
do
  echo -n .
  sleep 10;
  ISHDFSRUNNING=$(hdfs dfs -ls / 2> /dev/null | grep user > /dev/null 2> /dev/null)
  RET=$?
done
sleep 10;

echo ""
echo "HDFS (Namenode) is running ...."
echo ""

su - hdfs -c "hdfs dfs -mkdir /user/admin"
su - hdfs -c "hdfs dfs -chown -R admin:admin /user/admin"
su - hdfs -c "hdfs dfs -mkdir /user/willie"
su - hdfs -c "hdfs dfs -chown -R willie:willie /user/willie"
su - hdfs -c "hdfs dfs -mkdir /user/root"
su - hdfs -c "hdfs dfs -chown -R root:root /user/root"
su - hdfs -c "hdfs dfs -mkdir /user/hdfs"
su - hdfs -c "hdfs dfs -chown -R hdfs:hdfs /user/hdfs"
su - hdfs -c "hdfs dfs -mkdir /test"
su - hdfs -c "hdfs dfs -chmod 700 /test"

# Remove hdfs from the banned MR users list
sed -i 's/hdfs,//' /etc/hadoop/conf/container-executor.cfg
  
# Create the DAS role and Database. This mostly due to a chicken&egg problem. DAS insists on installing the DB itself, but won't create the user/db
systemctl enable postgresql-9.6
systemctl start postgresql-9.6
sleep 2
su - postgres -c "echo \"CREATE ROLE das LOGIN PASSWORD 'supersecret1'\" | psql -p 5435"
su - postgres -c "echo \"CREATE DATABASE das OWNER das ENCODING 'UTF-8'\" | psql -p 5435"

# Waiting for Ambari server to start
echo "Waiting for Hiveserver2 at ${FQDN}:10000 to respond to requests."
RET=1
 while [ $RET -eq 1 ]; do
  echo -n .; sleep 2
  echo "" | nc -v localhost 10000 > /dev/null 2> /dev/null
  RET=$?
done
echo ""
echo "Hiveserve2 is running ...."
echo ""

# Create a local auth file for beeline to use for automated authentication
cat > /etc/hive/conf/beeline-hs2-connection.xml << END
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
<property>
  <name>beeline.hs2.connection.user</name>
  <value>hive</value>
</property>
<property>
  <name>beeline.hs2.connection.password</name>
  <value>hive</value>
</property>
</configuration>
END



# Create Tag service in Ranger
#printf "\nConfigure Tag service in Ranger:\n"
#curl -i -u admin:${RAND_PW} -H "Content-type:application/json" -X POST  http://localhost:6080/service/plugins/services -d '{"name":"singlenode_tag","description":"","isEnabled":true,"configs":{},"type":"tag"}'

# Create some Ranger policies for
#printf "\n\nConfigure Hive service in Ranger:\n"
#curl -u admin:${RAND_PW} -i -s -X POST -H "Accept: application/json" -H "Content-Type: application/json" http://localhost:6080/service/public/v2/api/service -d '
#{
#    "configs": {
#        "ambari.service.check.user": "ambari-qa",
#        "jdbc.driverClassName": "org.apache.hive.jdbc.HiveDriver",
#        "jdbc.url": "jdbc:hive2://localhost:2181/;serviceDiscoveryMode=zooKeeper;zooKeeperNamespace=hiveserver2",
#        "password": "hive",
#        "policy.download.auth.users": "hive",
#        "policy.grantrevoke.auth.users": "hive",
#        "tag.download.auth.users": "hive",
#        "username": "hive"
#    },
#    "description": "Hive",
#    "isEnabled": true,
#    "name": "singlenode_hive",
#    "tagService": "singlenode_tag",
#    "type": "hive"
#}
#'

printf "\n\nModify an existing Hive policy, granting admin user access to all Databases, Tables, Columns:\n"
# First get the Policy ID
printf "\nFirst get the Policy ID for: all - database, table, column:\n"
POLICY_ID=$(curl -s -u admin:${RAND_PW} http://localhost:6080/service/plugins/policies/service/3 | jq '.policies[] | select(.name == "all - database, table, column") | .id')
# Then get just that policy, add the "admin" user to the "users" section, and save to disk
printf "\nThen get just that policy, add the "admin" user to the "users" section, and save to disk:\n"
curl -s -u admin:${RAND_PW} "http://localhost:6080/service/plugins/policies/service/3" | jq ".policies[] | select(.id == ${POLICY_ID})" | jq '.policyItems[].users = ["hive","ambari-qa","admin"]' > /tmp/ranger_hive_policy.json
# Now upload the modified policy back to Ranger
printf "\nLoad the ranger_hive_policy.json file back up to Ranger to save settings:\n"
curl -i -s -H 'Content-Type: application/json' -u admin:${RAND_PW} -X PUT --data @/tmp/ranger_hive_policy.json "http://localhost:6080/service/plugins/policies/${POLICY_ID}"


printf "\n\nNext, setup the HDFS Service in Ranger:\n"
#curl -u admin:${RAND_PW} -i -s -X POST -H "Accept: application/json" -H "Content-Type: application/json" http://localhost:6080/service/public/v2/api/service -d "
#{
#    \"configs\": {
#        \"ambari.service.check.user\": \"ambari-qa\",
#        \"commonNameForCertificate\": \"sandbox.hortonworks.com\",
#        \"fs.default.name\": \"hdfs://${FQDN}:8020\",
#        \"hadoop.rpc.protection\": \"authentication\",
#        \"hadoop.security.auth_to_local\": \"DEFAULT\",
#        \"hadoop.security.authentication\": \"simple\",
#        \"hadoop.security.authorization\": \"false\",
#        \"password\": \"hdfs\",
#        \"policy.download.auth.users\": \"hdfs\",
#        \"tag.download.auth.users\": \"hdfs\",
#        \"username\": \"hdfs\"
#    },
#    \"description\": \"HDFS\",
#    \"isEnabled\": true,
#    \"name\": \"singlenode_hadoop\",
#    \"tagService\": \"singlenode_tag\",
#    \"type\": \"hdfs\"
#}
#"
#curl -u admin:${RAND_PW} -i -s -X PUT -H "Accept: application/json" -H "Content-Type: application/json" 'http://localhost:6080/service/plugins/services/2' -d '
#{
#    "configs": {
#        "jdbc.driverClassName": "org.apache.hive.jdbc.HiveDriver",
#        "jdbc.url": "jdbc:hive2://localhost:2181/;serviceDiscoveryMode=zooKeeper;zooKeeperNamespace=hiveserver2",
#        "password": "*****",
#        "policy.download.auth.users": "hive",
#        "policy.grantrevoke.auth.users": "hive",
#        "tag.download.auth.users": "hive",
#        "username": "hive"
#    },
#    "createTime": 1531749971000,
#    "createdBy": "amb_ranger_admin",
#    "description": "hive repo",
#    "id": 2,
#    "isEnabled": true,
#    "name": "singlenode_hive",
#    "policyUpdateTime": 1534190920000,
#    "policyVersion": 9,
#    "tagUpdateTime": 1534181407000,
#    "tagVersion": 8,
#    "type": "hive",
#    "updateTime": 1534190920000,
#    "updatedBy": "Admin",
#    "version": 4,
#    "tagService":"singlenode_tag"
#}
#'

printf "\n\nCreate a new HDFS policy, granting admin,hive,willie user to /test folder:\n"
curl -u admin:${RAND_PW} -i -s -X POST -H "Accept: application/json" -H "Content-Type: application/json" http://localhost:6080/service/plugins/policies -d '
{"policyType":"0","name":"test","isEnabled":true,"isAuditEnabled":true,"description":"","resources":{"path":{"values":["/test"],"isRecursive":true}},"policyItems":[{"users":["admin","hive","willie"],"accesses":[{"type":"read","isAllowed":true},{"type":"write","isAllowed":true},{"type":"execute","isAllowed":true}]}],"denyPolicyItems":[],"allowExceptions":[],"denyExceptions":[],"service":"singlenode_hadoop"}'


# Create a new PII policy in Ranger Tags
printf "\n\nCreate a new PII policy in Ranger Tags:\n"
curl -u admin:${RAND_PW} -i -s -X POST -H "Accept: application/json" -H "Content-Type: application/json" http://localhost:6080/service/plugins/policies -d '
{"policyType":"0","name":"PII","isEnabled":true,"isAuditEnabled":true,"description":"","resources":{"tag":{"values":["PII"],"isRecursive":false,"isExcludes":false}},"policyItems":[{"users":["willie"],"accesses":[{"type":"hdfs:read","isAllowed":true},{"type":"hdfs:write","isAllowed":true},{"type":"hdfs:execute","isAllowed":true},{"type":"hive:select","isAllowed":true},{"type":"hive:update","isAllowed":true},{"type":"hive:create","isAllowed":true},{"type":"hive:drop","isAllowed":true},{"type":"hive:alter","isAllowed":true},{"type":"hive:index","isAllowed":true},{"type":"hive:lock","isAllowed":true},{"type":"hive:all","isAllowed":true},{"type":"hive:read","isAllowed":true},{"type":"hive:write","isAllowed":true},{"type":"hive:repladmin","isAllowed":true},{"type":"hive:serviceadmin","isAllowed":true}]}],"denyPolicyItems":[],"allowExceptions":[],"denyExceptions":[],"service":"singlenode_tag"}'


# Create a new group in Ranger called DataEngineers
printf "\n\nCreate a new group in Ranger called DataEngineers:\n"
NEWGROUP_ID=$(curl -s -H "Accept: application/json" -H 'Content-Type: application/json' -u admin:${RAND_PW} -X POST http://localhost:6080/service/xusers/secure/groups -d '{"name":"DataEngineers","description":""}' | jq -r '.id')
# Find the userID for Willie
printf "\nFind the user Willie:\n"
USER_ID=$(curl -s -H "Accept: application/json" -u admin:${RAND_PW} -H GET 'http://localhost:6080/service/xusers/users?sortBy=id' | jq '.vXUsers[] | select(.name == "willie") | .id')
GROUPID_LIST=$(curl -s -H "Accept: application/json" -u admin:${RAND_PW} -H GET 'http://localhost:6080/service/xusers/users?sortBy=id' | jq '.vXUsers[] | select(.name == "willie") ' | jq '.groupIdList[]')
# And add him to the DataEngineers group
printf "\nAnd add him to the DataEngineers group:\n"
curl -i -s -H "Accept: application/json" -H "Content-Type: application/json" -u admin:${RAND_PW} -X PUT 'http://localhost:6080/service/xusers/secure/users/willie' -d "{\"id\":${USER_ID},\"name\":\"willie\",\"firstName\":\"willie\",\"lastName\":\"willie\",\"description\":\"willie - add from Unix box\",\"groupIdList\":[${GROUPID_LIST},${NEWGROUP_ID}],\"groupNameList\":[\"willie\", \"DataEngineers\"],\"status\":1,\"isVisible\":1,\"userSource\":1,\"userRoleList\":[\"ROLE_USER\"],\"passwordConfirm\":\"\",\"emailAddress\":\"\"}"

# In Ranger, enable Deny Conditions in Resource Policies, and add RangerTimeOfDayMatcher evaluator to policyConditions[]
printf "\n\nIn Ranger, enable Deny Conditions in Resource Policies, add RangerTimeOfDayMatcher evaluator to policyConditions[]:\n"
curl -s -u admin:${RAND_PW} -X GET 'http://localhost:6080/service/public/v2/api/servicedef/name/hive' | jq '.policyConditions = [{"itemId":1,"name":"time-of-the-day","description":"Time of the day","label":"Time of the day","evaluator":"org.apache.ranger.plugin.conditionevaluator.RangerTimeOfDayMatcher"}] | .options.enableDenyAndExceptionsInPolicies = "true"' > /tmp/hive.json
# Load the hive.json file back up to Ranger to save settings
printf "\n\nLoad the hive.json file back up to Ranger to save settings:\n"
curl -H 'Content-Type: application/json' -u admin:${RAND_PW} -X PUT --data @/tmp/hive.json 'http://localhost:6080/service/public/v2/api/servicedef/name/hive'

# Setup Infra-SOLR with a ranger_audits collection 
printf "\n\nSetup Infra-SOLR with a ranger_audits collection:\n"
su - infra-solr -c "
cd /usr/hdp/3*/ranger-admin/contrib/solr_for_audit_setup;
/usr/lib/ambari-infra-solr/bin/solr zk -upconfig -n ranger_audits -d conf -z localhost:2181/infra-solr;
/usr/lib/ambari-infra-solr/bin/solr create_collection -c ranger_audits -d conf -shards 1 -replicationFactor 1;
"

# Creating Hive tables and Atlas lineage
printf "\nCreating Hive tables and Atlas lineage:\n"
cd /tmp
if [ ${USE_LOCAL_REPO} -eq 1 ]
then
     wget http://192.168.0.105/hwx/master.zip
else
     wget https://github.com/datacharmer/test_db/archive/master.zip
fi   	
unzip master.zip
cd test_db-master

mysql -u root -padmin < employees.sql

su - hive -c "beeline -n hive -u jdbc:hive2://localhost:10000 -e 'create database employees'"

# Create a tmp space for our sqoop commands
su - hive -c "hdfs dfs -mkdir /tmp/hive"

# Sqoop just the data to HDFS
su - hive -c "sqoop import --query 'select * from employees WHERE \$CONDITIONS' --connect jdbc:mysql://localhost:3306/employees --username root --password admin --target-dir /tmp/hive/employees_txt -m 1"
rm -f /home/hive/./QueryResult.java

su - hive -c "sqoop import --query 'select * from departments WHERE \$CONDITIONS' --connect jdbc:mysql://localhost:3306/employees --username root --password admin --target-dir /tmp/hive/departments_txt -m 1"
rm -f /home/hive/./QueryResult.java

su - hive -c "sqoop import --query 'select * from dept_emp WHERE \$CONDITIONS' --connect jdbc:mysql://localhost:3306/employees --username root --password admin --target-dir /tmp/hive/dept_emp_txt -m 1"
rm -f /home/hive/./QueryResult.java

# Create the three temporary txt tables in Hive
beeline -n hive -u jdbc:hive2://localhost:10000 -e 'CREATE EXTERNAL TABLE employees.employees_txt(
   emp_no int,
   birth_date string,
   first_name string,
   last_name string,
   gender char(1),
   hire_date string)
   ROW FORMAT DELIMITED
   FIELDS TERMINATED BY ","
   STORED AS TEXTFILE
   LOCATION "/tmp/hive/employees_txt";'

beeline -n hive -u jdbc:hive2://localhost:10000 -e 'CREATE EXTERNAL TABLE employees.departments_txt(
   dept_no string,
   dept_name string)
   ROW FORMAT DELIMITED
   FIELDS TERMINATED BY ","
   STORED AS TEXTFILE
   LOCATION "/tmp/hive/departments_txt";'

beeline -n hive -u jdbc:hive2://localhost:10000 -e 'CREATE EXTERNAL TABLE employees.dept_emp_txt(
   emp_no int,
   dept_no char(4),
   from_date string,
   to_date string)
   ROW FORMAT DELIMITED
   FIELDS TERMINATED BY ","
   STORED AS TEXTFILE
   LOCATION "/tmp/hive/dept_emp_txt";'

# Convert the txt tables to ORC
beeline -n hive -u jdbc:hive2://localhost:10000 -e 'create table employees.employees as select * from employees.employees_txt'
beeline -n hive -u jdbc:hive2://localhost:10000 -e 'create table employees.departments as select * from employees.departments_txt'
beeline -n hive -u jdbc:hive2://localhost:10000 -e 'create table employees.dept_emp as select * from employees.dept_emp_txt'

# Then drop the txt tables
beeline -n hive -u jdbc:hive2://localhost:10000 -e 'drop table employees.employees_txt'
beeline -n hive -u jdbc:hive2://localhost:10000 -e 'drop table employees.departments_txt'
beeline -n hive -u jdbc:hive2://localhost:10000 -e 'drop table employees.dept_emp_txt'

# Join the three tables together
su - hive -c "beeline -n hive -u jdbc:hive2://localhost:10000 -e \"use employees; create table emp_dept_flat stored as orc as select e.emp_no, concat(e.last_name, ', ', e.first_name) as full_name, e.first_name, e.last_name, e.birth_date, e.gender, e.hire_date, d.dept_no, d.dept_name, de.from_date, de.to_date from employees e, departments d, dept_emp de where e.emp_no = de.emp_no and de.dept_no = d.dept_no\""

# Create a view by joining two tables together
su - hive -c "beeline -n hive -u jdbc:hive2://localhost:10000 -e \"use employees; create view employee_employment_date as select employees.*, dept_emp.from_date, dept_emp.to_date from employees, dept_emp where employees.emp_no = dept_emp.emp_no\""

# Create another view by joining the previous view and underlying table together. This makes for a nice lineage graph
su - hive -c "beeline -n hive -u jdbc:hive2://localhost:10000 -e \"use employees; create view employee_and_department as select employee_employment_date.first_name, employee_employment_date.last_name, emp_dept_flat.dept_name from employee_employment_date, emp_dept_flat where employee_employment_date.emp_no = emp_dept_flat.emp_no\""


# In Atlas, create a PII tag
printf "\nCreate PII tag in Atlas\n"
curl -i -u "admin:${RAND_PW}" -H "Content-type:application/json" -X POST http://localhost:21000/api/atlas/v2/types/typedefs?type=classification -d '{"classificationDefs":[{"name":"PII","description":"","superTypes":[],"attributeDefs":[]}],"entityDefs":[],"enumDefs":[],"structDefs":[]}'

# In Atlas, find out the GUID of the employees.employees table, so that we can use it in the next curl call
cat > "/tmp/at.job" << EOF
GUID=\$(curl -s -k -u "admin:${RAND_PW}" -H "Content-type:application/json" -X POST http://localhost:21000/api/atlas/v2/search/basic -d '{"excludeDeletedEntities":true,"entityFilters":null,"tagFilters":null,"attributes":[],"query":"employees.employees","limit":25,"offset":0,"typeName":"hive_table","classification":null}' | jq -r '.entities[0].guid');

# In Atlas, assign the PII to the employees table 
echo "Assign the PII tag to the employees entity (table) in Atlas"
curl -i -u "admin:${RAND_PW}" -H "Content-type:application/json" -X POST http://localhost:21000/api/atlas/v2/entity/bulk/classification -d "{\"classification\":{\"typeName\":\"PII\",\"attributes\":{}},\"entityGuids\":[\"\${GUID}\"]}";

#docker run centos/httpd-24-centos7:latest
EOF
cat /tmp/at.job | at now +1min

# In Ambari, create the willie user
printf "\nAdd user willie to Ambari:\n"
curl -i -u admin:admin -H "X-Requested-By: ambari" -X POST http://localhost:8080/api/v1/users -d "{\"Users/user_name\":\"willie\",\"Users/password\":\"${RAND_PW}\",\"Users/active\":true,\"Users/admin\":false}"

# Then, add user willie to the Hive view
#printf "\nAdd user willie to Ambari Hive View:\n"
#curl -i -u admin:admin -H "X-Requested-By: ambari" -X PUT http://localhost:8080/api/v1/views/HIVE/versions/1.5.0/instances/AUTO_HIVE_INSTANCE/privileges -d '[{"PrivilegeInfo":{"permission_name":"VIEW.USER","principal_name":"willie","principal_type":"USER"}},{"PrivilegeInfo":{"permission_name":"VIEW.USER","principal_name":"CLUSTER.ADMINISTRATOR","principal_type":"ROLE"}},{"PrivilegeInfo":{"permission_name":"VIEW.USER","principal_name":"CLUSTER.OPERATOR","principal_type":"ROLE"}},{"PrivilegeInfo":{"permission_name":"VIEW.USER","principal_name":"SERVICE.OPERATOR","principal_type":"ROLE"}},{"PrivilegeInfo":{"permission_name":"VIEW.USER","principal_name":"SERVICE.ADMINISTRATOR","principal_type":"ROLE"}},{"PrivilegeInfo":{"permission_name":"VIEW.USER","principal_name":"CLUSTER.USER","principal_type":"ROLE"}}]'

# Change the admin user password as well
printf "\nChange admin user's password in Ambari:\n"
curl -i -u admin:admin -H "X-Requested-By: ambari" -X PUT http://localhost:8080/api/v1/users/admin -d "{\"Users/password\":\"${RAND_PW}\",\"Users/old_password\":\"admin\"}"


# Clear SOLR index:
#curl "http://${FQDN}:8886/solr/hadoop_logs_shard0_replica1/update?stream.body=<delete><query>*:*</query></delete>&commit=true"
#curl "http://${FQDN}:8886/solr/hadoop_logs_shard1_replica1/update?stream.body=<delete><query>*:*</query></delete>&commit=true"


# Deploy David Streever's HDP-cli
cd /root
wget https://github.com/dstreev/hadoop-cli/releases/download/2.0.21-SNAPSHOT/hadoop.cli-2.0.21-SNAPSHOT-3.1.tar.gz
tar xzvf hadoop.cli-2.0.21-SNAPSHOT-3.1.tar.gz
cd hadoop-cli-3.1/
./setup.sh

echo ""
echo "###########################################################" | tee /root/ambari_install.txt
echo "# YOUR CLUSTER IS NOW READY!                               " | tee -a /root/ambari_install.txt
echo "# Ambari: http://$FQDN:8080                                " | tee -a /root/ambari_install.txt
echo "# username: admin    password: ${RAND_PW}                  " | tee -a /root/ambari_install.txt
echo "# username: willie   password: ${RAND_PW}                  " | tee -a /root/ambari_install.txt
echo "#                                                          " | tee -a /root/ambari_install.txt
echo "# KDC REALM: $REALM                                        " | tee -a /root/ambari_install.txt 
echo "# principal: admin/admin@$REALM                            " | tee -a /root/ambari_install.txt
echo "# password:  hadoop                                        " | tee -a /root/ambari_install.txt
echo "#                                                          " | tee -a /root/ambari_install.txt
echo "# Username/Password info stored in /root/ambari_install.txt"
echo "###########################################################" | tee -a /root/ambari_install.txt
echo ""

echo "Add the following to your hosts file:" | tee -a /root/ambari_install.txt
ipaddr=$(hostname -I | awk '{print $1}')
echo $ipaddr | grep '192.168.0.' > /dev/null
if [ $? -eq 0 ]
then
    echo "${ipaddr} $(hostname -f)" | tee -a /root/ambari_install.txt
else
    ipaddr=$(curl -s ipinfo.io/ip)
    echo "${ipaddr} ${FQDN}" | tee -a /root/ambari_install.txt
fi
echo ""

echo "echo '" >> /root/.bash_profile
cat /root/ambari_install.txt  >> /root/.bash_profile
echo "'" >> /root/.bash_profile

