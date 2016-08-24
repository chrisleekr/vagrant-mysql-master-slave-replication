#!/usr/bin/env bash

# Variables
DBNAME=sample
DBUSER=root
DBPASSWD=root
DBDIRPATH=/var/lib/mysql_vagrant
MASTER_IP='192.168.100.11'
REPLICA_IP='192.168.100.12'
REPLICA_SSH_USER='vagrant'
REPLICA_SSH_PASS='vagrant'

#echo -e "\n--- Updating package list and upgrade system... --- \n"
# Download and Install the Latest Updates for the OS
#sudo apt-get update && sudo apt-get upgrade -y

# Set the Server Timezone to CST
if [ ! -f /var/log/setup_timezone ]
then
	echo -e "\n--- Setting timezone ---\n"
	echo "Australia/Melbourne" > /etc/timezone
	sudo dpkg-reconfigure -f noninteractive tzdata

	touch /var/log/setup_timezone
fi

# Enable Ubuntu Firewall and allow SSH & MySQL Ports
if [ ! -f /var/log/setup_firewall ]
then 
	echo -e "\n--- Setup firewall ---\n"
	yes y | sudo ufw enable
	sudo ufw allow 22
	sudo ufw allow 3306

	touch /var/log/setup_firewall
fi 

if [ ! -f /var/log/setup_mysql ]
then

	echo -e "\n--- Install MySQL specific packages and settings ---\n"
	sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password $DBPASSWD"
	sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $DBPASSWD"
	sudo apt-get -y install mysql-server mysql-client 


	echo -e "\n--- Setting up MySQL user and db ---\n"
	sudo mysql -uroot -p$DBPASSWD -e "CREATE DATABASE IF NOT EXISTS $DBNAME" 
	sudo mysql -uroot -p$DBPASSWD -e "grant all privileges on $DBNAME.* to '$DBUSER'@'localhost' identified by '$DBPASSWD'"

	# Set up root user's host to be accessible from any remote
	echo -e "\n--- Set up root user's host to be accessible from any remote ---\n"
	sudo mysql -uroot -p$DBPASSWD -e 'USE mysql; UPDATE `user` SET `Host`="%" WHERE `User`="root" AND `Host`="localhost"; DELETE FROM `user` WHERE `Host` != "%" AND `User`="root"; FLUSH PRIVILEGES;'

	# Create replication user in master machine
	echo -e "\n---- Create replication user in master machine\n";
	mysql -uroot -p$DBPASSWD -e "CREATE USER 'repl'@'%' IDENTIFIED BY 'mysqluser';GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';FLUSH PRIVILEGES;"

	# Move initial database file to persistent directory
	echo -e "\n--- Move initial database file to persistent directory ---\n"

	sudo service mysql stop

	sudo chown -R mysql:mysql $DBDIRPATH
	sudo rm -rf $DBDIRPATH/*
	sudo cp -r -p /var/lib/mysql/* $DBDIRPATH

	sudo mv /var/lib/mysql /var/lib/mysql.bak
	echo "alias /var/lib/mysql/ -> $DBDIRPATH," | sudo tee -a /etc/apparmor.d/tunables/alias
	sudo /etc/init.d/apparmor reload

	sudo cp /vagrant/config/master/my-master.cnf /etc/mysql/conf.d/my_override.cnf
	touch /var/log/setup_mysql
fi


sudo service mysql restart

if [ ! -f /var/log/setup_replication ]
then
	echo -e "\n--- Setting up MySQL replication ---\n"
	sudo apt-get install sshpass -y


	# Check slave is up or not
	IS_HOST_AVAILABLE=false
	while ! $IS_HOST_AVAILABLE 
	do 
		echo -e "\n---- Checking slave connection\n"
		SLAVE_ALIVE=$(ping -s 64 "$REPLICA_IP" -c 1 | grep packet | awk '{print $(NF-4)}')
		if [ $SLAVE_ALIVE == "0%" ]
		then
			echo -e "\n---- Slave is accessible!\n"

			IS_MYSQL_SETUP=false
			while ! $IS_MYSQL_SETUP
			do
				echo -e "\n---- Check MySQL is setup or not\n"
				FILE_SETUP_MYSQL=$(sshpass -p "$REPLICA_SSH_PASS" ssh -o StrictHostKeyChecking=no $REPLICA_SSH_USER@$REPLICA_IP "[ -f /var/log/setup_mysql ] && echo \"Found\" || echo \"Not found\"")
				echo -e "\n----- MySQL setup file $FILE_SETUP_MYSQL\n"
				if [ $FILE_SETUP_MYSQL == "Found" ]
				then
					echo -e "\n----- MySQL is configured. Proceed to next step\n"
					IS_MYSQL_SETUP=true
					IS_HOST_AVAILABLE=true
				else
					echo -e "\n----- MySQL is not configured; checking after 10 secs\n"
					sleep 10
				fi
			done
		else 
			echo -e "\n----- Slave is not accessible; checking after 10 secs\n"
			sleep 10
		fi
	done

	
	
	# Get database dump
	echo -e "\n---- Dump sample database to SQL\n";
	mysqldump -uroot -p$DBPASSWD --opt sample > /vagrant/config/sample.sql

	# Get log file and position from master machine
	CURRENT_LOGINFO=$(mysql -uroot -p$DBPASSWD --execute='SHOW MASTER STATUS' -AN)
	CURRENT_LOG=`echo $CURRENT_LOGINFO | awk '{print $1}'`
	CURRENT_POS=`echo $CURRENT_LOGINFO | awk '{print $2}'`
	
	echo -e "\n---- Got current log file $CURRENT_LOG \n";
	echo -e "\n---- Got current log position $CURRENT_POS \n";

	# Import database dump to slave machine
	echo -e "\n---- Import database dump to slave machine\n";
	sshpass -p "$REPLICA_SSH_PASS" ssh -o StrictHostKeyChecking=no $REPLICA_SSH_USER@$REPLICA_IP "mysql -uroot -p$DBPASSWD sample < /vagrant/config/sample.sql"

	# Change master host to slave log file and position in slave machine
	echo -e "\n---- Change master host to slave log file and position in slave machine\n";
	sshpass -p "$REPLICA_SSH_PASS" ssh -o StrictHostKeyChecking=no $REPLICA_SSH_USER@$REPLICA_IP "mysql -uroot -p$DBPASSWD -e \"SLAVE STOP;CHANGE MASTER TO MASTER_HOST='$MASTER_IP', MASTER_USER='repl', MASTER_PASSWORD='mysqluser', MASTER_LOG_FILE='$CURRENT_LOG', MASTER_LOG_POS=$CURRENT_POS;START SLAVE;\""

	# Commented out to run replication scripts every provision
	#touch /var/log/setup_replication
fi


if [ ! -f /var/log/setup_replication_test ]
then
	echo -e "\n---- Testing replication\n";
	mysql -uroot -p$DBPASSWD -e "use sample;create table users(id int not null auto_increment, primary key(id), username varchar(30) not null);insert into users (username) values ('foo');insert into users (username) values ('bar');"

	touch /var/log/setup_replication_test
fi