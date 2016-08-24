# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.synced_folder ".", "/vagrant", mount_options: ["dmode=700,fmode=600"]
  config.vm.synced_folder "./config", "/vagrant/config", mount_options: ["dmode=755,fmode=755"]
  
  # run slave first
  config.vm.define "mysqlslave" do |mysqlslave|
    mysqlslave.vm.box = "ubuntu/precise64"
    mysqlslave.vm.hostname = 'mysqlslave'
    mysqlslave.vm.synced_folder "./data/slave", "/var/lib/mysql_vagrant" , id: "mysql",
    owner: 108, group: 113,  # owner: "mysql", group: "mysql",
    mount_options: ["dmode=775,fmode=664"]

    mysqlslave.vm.network :private_network, ip: "192.168.100.12"

    mysqlslave.vm.provider :virtualbox do |v|
      v.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      v.customize ["modifyvm", :id, "--memory", 512]
      v.customize ["modifyvm", :id, "--name", "mysqlslave"]
    end

    mysqlslave.vm.provision :shell, path: "bootstrap-slave.sh"
  end

  config.vm.define "mysqlmaster" do |mysqlmaster|
    mysqlmaster.vm.box = "ubuntu/precise64"
    mysqlmaster.vm.hostname = 'mysqlmaster'
    mysqlmaster.vm.synced_folder "./data/master", "/var/lib/mysql_vagrant" , id: "mysql",
    owner: 108, group: 113,  # owner: "mysql", group: "mysql",
    mount_options: ["dmode=775,fmode=664"]

    mysqlmaster.vm.network :private_network, ip: "192.168.100.11"

    mysqlmaster.vm.provider :virtualbox do |v|
      v.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      v.customize ["modifyvm", :id, "--memory", 512]
      v.customize ["modifyvm", :id, "--name", "mysqlmaster"]      
    end

    mysqlmaster.vm.provision :shell, path: "bootstrap-master.sh"

  end  
end
