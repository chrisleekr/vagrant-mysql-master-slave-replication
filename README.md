# vagrant-mysql-master-slave-replication
Vagrantfile to spin up MySQL Master-Slave replication with persistent data storage

Note: This project is created for just practice. Not suitable for production use.


# Prerequisites
* Vagrant 1.8.1+: <http://www.vagrantup.com/>
* VirtualBox: <https://www.virtualbox.org/>

# Usage
```
    $ git clone https://github.com/chrisleekr/vagrant-mysql-master-slave-replication.git
    $ vagrant up
```
After vagrant machines are running, you can connect MySQL to:
* Master machine: 192.168.100.11
* Slave machine: 192.168.100.12

After vagrant halt/suspend, need to run provisioning scripts again to synchronize MySQL from master to slave machine
```
    $ vagrant halt
    $ vagrant up && vagrant provision
```

If having the error message 'The guest additions on this VM do not match the install version of VirtualBox!', then run following command before vagrant up
```
    $ vagrant plugin install vagrant-vbguest
```
 
# Environments
* VM Box: Ubuntu/prcise64
    * Master MySQL
    * Private IP: 192.168.100.11
    * Hostname: mysqlmaster
    * Database Name: sample
    * Database Username: root
    * Database Password: root 
* Slave MySQL
    * Private IP: 192.168.100.12
    * Hostname: mysqlslave
    * Database Name: sample
    * Database Username: root
    * Database Password: root
 
# How it works
1. MySQL slave machine will be launched first. 
    * Vagrant provisioning script will update package list and upgrade system (Currently commented out. If need, uncomment it)
    * Set up timezone to Australia/Melbourne
    * Configure firewall to enable 22/3306 ports (may not need?)
    * Install MySQL server and client
    * Configure vagrant synced folder as persistent directory and move initial database file to persistent directory
    * Copy config/my-slave.cnf to /etc/mysql/conf.d/my_override.cnf, which will override default MySQL configurations
    * Create database and grant privileges to root user
    * Set up root user's host to be accessible from any remote 
    * Restart MySQL service
2. MySQL master machine will be launched following.
    * Vagrant provisioning script will update package list and upgrade system (Currently commented out. If need, uncomment it)
    * Set up timezone to Australia/Melbourne
    * Configure firewall to enable 22/3306 ports (may not need?)
    * Install MySQL server and client
    * Configure vagrant synced folder as persistent directory and move initial database file to persistent directory
    * Copy config/my-master.cnf to /etc/mysql/conf.d/my_override.cnf, which will override default MySQL configurations
    * Create database and grant privileges to root user
    * Set up root user's host to be accessible from any remote 
    * Create replication user in MySQL master machine
    * Restart MySQL service
    * Install sshpass to access ssh to MySQL slave machine
    * Check slave machine is up and running and MySQL is configured by checking /var/log/setup_mysql
    * Dump database to SQL file from master machine
    * Get current log file and position from master machine
    * Log into MySQL slave machine and import dumped SQL file to sample database
    * Set slave machine to connect master machine for reading the master binary log
    * Create test transaction in master machine
    
# Screenshots
![Alt text](/screenshots/screenshot1.png?raw=true "vagrant up")
![Alt text](/screenshots/screenshot2.png?raw=true "MySQL master machine")
![Alt text](/screenshots/screenshot3.png?raw=true "MySQL slave machine")

# Todo
* Vagrant MySQL Master-Master Replication
