#!/usr/bin/env bash

# Variables
DBNAME=sample
DBUSER=root
DBPASSWD=root
DBDIRPATH=/var/lib/mysql_vagrant
DBCONFIG_FILE=/vagrant/config/master/my-master.cnf
MASTER_IP='192.168.100.11'
REPLICA_IP='192.168.100.12'
REPLICA_SSH_USER='vagrant'
REPLICA_SSH_PASS='vagrant'


#echo -e "--- Updating package list and upgrade system... --- "
# Download and Install the Latest Updates for the OS
#sudo apt-get update && sudo apt-get upgrade -y

# Set the Server Timezone to CST
if [ ! -f /var/log/setup_timezone ]
then
	echo -e "--- Setting timezone ---"
	echo "Australia/Melbourne" > /etc/timezone
	sudo dpkg-reconfigure -f noninteractive tzdata

	touch /var/log/setup_timezone
fi

# Enable Ubuntu Firewall and allow SSH & MySQL Ports
if [ ! -f /var/log/setup_firewall ]
then 
	echo -e "--- Setup firewall ---"
	yes y | sudo ufw enable
	sudo ufw allow 22
	sudo ufw allow 3306

	touch /var/log/setup_firewall
fi 

# Returns true once mysql can connect.
mysql_ready() {
    sudo mysqladmin ping --host=localhost --user=$DBUSER --password=$DBPASSWD > /dev/null 2>&1
}

if [ ! -f /var/log/setup_mysql ]
then

	echo -e "--- Install MySQL specific packages and settings ---"
	sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password $DBPASSWD"
	sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $DBPASSWD"
	sudo apt-get -y install mysql-server mysql-client 

    # Move initial database file to persistent directory
	echo -e "--- Move initial database file to persistent directory ---"

	sudo service mysql stop

	sudo chown -R mysql:mysql $DBDIRPATH
	sudo rm -rf $DBDIRPATH/*
	sudo cp -r -p /var/lib/mysql/* $DBDIRPATH

	sudo mv /var/lib/mysql /var/lib/mysql.bak
	echo "alias /var/lib/mysql/ -> $DBDIRPATH," | sudo tee -a /etc/apparmor.d/tunables/alias
	sudo /etc/init.d/apparmor reload

    sudo cp $DBCONFIG_FILE /etc/mysql/conf.d/my_override.cnf
    sudo service mysql start

    while !(mysql_ready)
    do
       sleep 10s
       echo "---- Waiting for MySQL Connection... Check again after 10 secs..."
    done

	echo -e "--- Setting up MySQL user and db ---"
	sudo mysql -uroot -p$DBPASSWD -e "CREATE DATABASE IF NOT EXISTS $DBNAME" 
	sudo mysql -uroot -p$DBPASSWD -e "GRANT ALL PRIVILEGES ON $DBNAME.* TO '$DBUSER'@'localhost' IDENTIFIED BY '$DBPASSWD'"


	# Set up root user's host to be accessible from any remote
	echo -e "--- Set up root user's host to be accessible from any remote ---"
	sudo mysql -uroot -p$DBPASSWD -e 'USE mysql; UPDATE `user` SET `Host`="%" WHERE `User`="root" AND `Host`="localhost"; DELETE FROM `user` WHERE `Host` != "%" AND `User`="root"; FLUSH PRIVILEGES;'

	# Create replication user in master machine
	echo -e "---- Create replication user in master machine"
	mysql -uroot -p$DBPASSWD -e "CREATE USER 'repl'@'%' IDENTIFIED BY 'mysqluser';GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';FLUSH PRIVILEGES;"

    sudo service mysql restart

	touch /var/log/setup_mysql
else
    # If already initialized, then just restart MySQL server
    sudo service mysql start

    while !(mysql_ready)
    do
       sleep 10s
       echo "---- Waiting for MySQL Connection... Check again after 10 secs..."
    done
fi


if [ ! -f /var/log/setup_replication ]
then
	echo -e "--- Setting up MySQL replication ---"
	sudo apt-get install sshpass -y


	# Check slave is up or not
	IS_HOST_AVAILABLE=false
	while ! $IS_HOST_AVAILABLE 
	do 
		echo -e "---- Checking slave connection"
		SLAVE_ALIVE=$(ping -s 64 "$REPLICA_IP" -c 1 | grep packet | awk '{print $(NF-4)}')
		if [ $SLAVE_ALIVE == "0%" ]
		then
			echo -e "---- Slave is accessible!"

			IS_MYSQL_SETUP=false
			while ! $IS_MYSQL_SETUP
			do
				echo -e "---- Check MySQL is setup or not"
				FILE_SETUP_MYSQL=$(sshpass -p "$REPLICA_SSH_PASS" ssh -o StrictHostKeyChecking=no $REPLICA_SSH_USER@$REPLICA_IP "[ -f /var/log/setup_mysql ] && echo \"Found\" || echo \"Not found\"")
				echo -e "----- MySQL setup file $FILE_SETUP_MYSQL"
				if [ $FILE_SETUP_MYSQL == "Found" ]
				then
					echo -e "----- MySQL is configured. Proceed to next step"
					IS_MYSQL_SETUP=true
					IS_HOST_AVAILABLE=true
				else
					echo -e "----- MySQL is not configured; checking after 10 secs"
					sleep 10
				fi
			done
		else 
			echo -e "----- Slave is not accessible; checking after 10 secs"
			sleep 10
		fi
	done

	
	
	# Get database dump
	echo -e "---- Dump sample database to SQL"
	mysqldump -uroot -p$DBPASSWD --opt sample > /vagrant/config/sample.sql

	# Get log file and position from master machine
	CURRENT_LOGINFO=$(mysql -uroot -p$DBPASSWD --execute='SHOW MASTER STATUS' -AN)
	CURRENT_LOG=`echo $CURRENT_LOGINFO | awk '{print $1}'`
	CURRENT_POS=`echo $CURRENT_LOGINFO | awk '{print $2}'`
	
	echo -e "---- Got current log file $CURRENT_LOG "
	echo -e "---- Got current log position $CURRENT_POS"

	# Import database dump to slave machine
	echo -e "---- Import database dump to slave machine"
	sshpass -p "$REPLICA_SSH_PASS" ssh -o StrictHostKeyChecking=no $REPLICA_SSH_USER@$REPLICA_IP "mysql -uroot -p$DBPASSWD sample < /vagrant/config/sample.sql"

	# Change master host to slave log file and position in slave machine
	echo -e "---- Change master host to slave log file and position in slave machine"
	sshpass -p "$REPLICA_SSH_PASS" ssh -o StrictHostKeyChecking=no $REPLICA_SSH_USER@$REPLICA_IP "mysql -uroot -p$DBPASSWD -e \"SLAVE STOP;CHANGE MASTER TO MASTER_HOST='$MASTER_IP', MASTER_USER='repl', MASTER_PASSWORD='mysqluser', MASTER_LOG_FILE='$CURRENT_LOG', MASTER_LOG_POS=$CURRENT_POS;START SLAVE;\""

	# Commented out to run replication scripts every provision
	#touch /var/log/setup_replication
fi


if [ ! -f /var/log/setup_replication_test ]
then
	echo -e "---- Testing replication"
	mysql -uroot -p$DBPASSWD -e "USE sample;CREATE TABLE users(id INT NOT NULL AUTO_INCREMENT, PRIMARY KEY(id), username VARCHAR(30) NOT NULL);INSERT INTO users (username) VALUES ('foo');INSERT INTO users (username) VALUES ('bar');"

	touch /var/log/setup_replication_test
fi