#!/usr/bin/env bash

# Variables
DBNAME=sample
DBUSER=root
DBPASSWD=root
DBDIRPATH=/var/lib/mysql_vagrant
DBCONFIG_FILE=/vagrant/config/slave/my-slave.cnf

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





