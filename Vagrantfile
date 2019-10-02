#!/usr/bin/env ruby

VAGRANTFILE_API_VERSION = '2'.freeze
Vagrant.configure('2') do |config|
  config.vm.box = 'ubuntu/bionic64'
  config.disksize.size = '16GB'
  config.vm.define 'elementary-builder'
  config.vm.provision 'shell', path: 'vagrant.sh'
end
