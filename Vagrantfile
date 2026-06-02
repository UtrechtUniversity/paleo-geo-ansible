# coding: utf-8
# copyright Utrecht University
# -*- mode: ruby -*-
# vi: set ft=ruby :

# Vagrant configuration for a Paleo Earth development VM.
VAGRANT_DEFAULT_PROVIDER = "libvirt"
VAGRANTFILE_API_VERSION  = "2"

BOX     = "almalinux/9"
CPU     = 2
RAM     = 2048
DOMAIN  = ".paleo.test"
NETWORK = "192.168.70."
NETMASK = "255.255.255.0"

HOSTS = {
  "www" => [NETWORK + "10", CPU, RAM, BOX],
}

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.ssh.insert_key = false

  HOSTS.each do |name, cfg|
    ipaddr, cpu, ram, box = cfg

    config.vm.define name do |machine|
      machine.vm.box = box

      machine.vm.provider :libvirt do |libvirt|
        libvirt.driver = "kvm"
        libvirt.cpus   = cpu
        libvirt.memory = ram
      end

      machine.vm.hostname        = name + DOMAIN
      machine.vm.network "private_network", ip: ipaddr, netmask: NETMASK
      machine.vm.synced_folder ".", "/vagrant", disabled: true
      machine.vm.provision "shell",
        inline: "sudo timedatectl set-timezone Europe/Amsterdam"
    end
  end
end
