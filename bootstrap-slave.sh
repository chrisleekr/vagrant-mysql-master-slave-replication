#!/usr/bin/env bash

# Variables
DBNAME=sample
DBUSER=root
DBPASSWD=root

echo -e "\n--- Updating package list and upgrade system... --- \n"
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

	# echo -e "\n--- Setting up MySQL user and db ---\n"
	sudo mysql -uroot -p$DBPASSWD -e "CREATE DATABASE $DBNAME" 
	sudo mysql -uroot -p$DBPASSWD -e "grant all privileges on $DBNAME.* to '$DBUSER'@'localhost' identified by '$DBPASSWD'"

	# Set up root user's host to be accessible from any remote
	echo -e "\n--- Set up root user's host to be accessible from any remote ---\n"
	sudo mysql -uroot -p$DBPASSWD -e 'USE mysql; UPDATE `user` SET `Host`="%" WHERE `User`="root" AND `Host`="localhost"; DELETE FROM `user` WHERE `Host` != "%" AND `User`="root"; FLUSH PRIVILEGES;'

	touch /var/log/setup_mysql
fi

sudo cp /vagrant/config/my-slave.cnf /etc/mysql/conf.d/my_override.cnf
sudo service mysql restart


