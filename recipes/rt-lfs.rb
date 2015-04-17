#
# Cookbook Name:: nedge-config
# Recipe:: rt-lfs
#
# Copyright 2014, Nexenta
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#

require 'json'

user = ENV['USER']
name = "disk"

if node[:prefix]
    prefix = node[:prefix]
else
    prefix = "/opt/nedge"
end

if node[:data]
    data = node[:data]
else
    data = "/data"
end

directory data do
    owner   user
    group   user
    mode    00755
end

if node[:disks]
    disks = node[:disks][:devices]
else
    disks = node["block_device"].
        select {|k,v| v["model"] != nil && v["removable"] == "0"}.keys.
        keep_if {|k| (node[:filesystem]["/dev/" + k] == nil &&
                  node[:filesystem]["/dev/" + k + "1"] == nil) ||
                 node[:filesystem]["/dev/" + k] != nil &&
                 node[:filesystem]["/dev/" + k]["mount"] == nil}.
    keep_if{|k| ! system "pvs /dev/#{k} 2>/dev/null >/dev/null"}
end

ids = []
disks.each do |disk|
    ids << `ls -l /dev/disk/by-id |awk '/#{disk}/{print $9}'|head -1`.split[0]
end

if File.exist?(prefix)
    begin
        disksJson = JSON.parse(`cd "#{prefix}"; . ./env.sh; nefclient procman findWorkers`)
    rescue Exception => e
        diskJson = {}
    end
    if(disksJson["response"])
        disk_enabled = disksJson["response"].keep_if{ |v| v["name"] == name }[0]["enabled"] == true
    else
        disk_enabled = false
    end
end

execute "enable disk" do
    command <<-COMMAND
        cd "#{prefix}"
        . ./env.sh
        nefadm enable '#{name}'
    COMMAND
    not_if { disk_enabled == true }
    retries 3
    retry_delay 20
end

device_list = Array.new
ids.each do |disk|
    name = "#{disk}"
    path = "#{data}/#{disk}"
    device = "/dev/disk/by-id/#{disk}"

    json_device = JSON.generate({:device => device})
    json_path = JSON.generate({:mountPoint => path})
    json_mount = JSON.generate({:device => device, :mountPoint => path})
    execute "#{disk}" do
        command <<-COMMAND
            cd "#{prefix}"
            . ./env.sh
            nefclient disk diskFormat '#{json_device}'
            nefclient disk tuneFS '#{json_device}'
            nefclient disk createMountPoint '#{json_path}'
            nefclient disk mountDisk '#{json_mount}'
            nefclient disk addFsTabEntry '#{json_mount}'
        COMMAND
        retries 3
        retry_delay 20
    end
    device_list.push({:name => name, :path => path, :device => device})
end

execute "set devices" do
    property = {:module => "rt-lfs"}
    property[:name] = "devices"
    property[:value] = device_list
    json_property = JSON.generate(property)
    command <<-COMMAND
        cd "#{prefix}"
        . ./env.sh
        nefclient sysconfig setProperty '#{json_property}'
    COMMAND
    not_if { device_list.length < 1 }
    retries 3
    retry_delay 20
end

sleep(30)
