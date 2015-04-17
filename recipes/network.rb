#
# Cookbook Name:: nedge-config
# Recipe:: corosync
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

if node[:prefix]
    prefix = node[:prefix]
else
    prefix = "/opt/nedge"
end

if node.has_key?('NEDGE_NETPLAN')
    nedge_netplan = node['NEDGE_NETPLAN']
    if nedge_netplan.has_key?('override-interfaces')
        interface = nedge_netplan['override-interfaces']
    end
else
    raise "Required parameter 'NEDGE_NETPLAN' not found!"
end

if node.has_key?('NEDGE_NODE_PROFILE')
    nedge_node_profile = node['NEDGE_NODE_PROFILE']
else
    raise "Required parameter 'NEDGE_NODE_PROFILE' not found!"
end

execute "up override interface" do
    command <<-COMMAND
        ifconfig '#{interface}' up
    COMMAND
    only_if { nedge_netplan.has_key?('override-interfaces') }
end

execute "set node id" do
    nodeid = node.macaddress.split(':').last(4).join.hex.to_s
    property = {:module => :corosync}
    property[:name] = :nodeid
    property[:value] = nodeid
    json_property = JSON.generate(property)
    command <<-COMMAND
        cd "#{prefix}"
        . ./env.sh
        nefclient sysconfig setProperty '#{json_property}'
    COMMAND
    retries 3
    retry_delay 20
end

execute "set netplan" do
    property = {:module => :net}
    property[:name] = :plan
    property[:value] = nedge_netplan
    json_property = JSON.generate(property)
    command <<-COMMAND
        cd "#{prefix}"
        . ./env.sh
        nefclient sysconfig setProperty '#{json_property}'
    COMMAND
    retries 3
    retry_delay 20
end

execute "set profile" do
    property = {:module => :net}
    property[:name] = :profile
    property[:value] = nedge_node_profile
    json_property = JSON.generate(property)
    command <<-COMMAND
        cd "#{prefix}"
        . ./env.sh
        nefclient sysconfig setProperty '#{json_property}'
    COMMAND
    retries 3
    retry_delay 20
end

execute "start network" do
    name = "network"
    command <<-COMMAND
        cd /opt/nedge
        . ./env.sh
        nefadm enable '#{name}'
    COMMAND
    not_if do JSON.parse(`cd /opt/nedge; . ./env.sh; nefclient procman findWorkers`)["response"].keep_if{ |v| v["name"] == name }[0]["enabled"] == true end
    retries 3
    retry_delay 20
end

setagg = false
if node.has_key?("aggregator")
    if node["aggregator"] == 1
        setagg = true
    end
else
    ret = system("sleep 3; test -x /opt/nedge/sbin/corosync-quorumtool")
    if ret
        m = /^Nodes:\s+(\d+)\s*$/.match(`cd /opt/nedge; . ./env.sh; corosync-quorumtool`)
        if(m and Integer(m[1]) < 2)
            setagg = true
        end
    end
end

execute "set aggregator" do
    flush_property = {:module => :auditd}
    flush_property[:name] = :flushInterval
    flush_property[:value] = 3
    flush_json_property = JSON.generate(flush_property)
    aggr_property = {:module => :auditd}
    aggr_property[:name] = :isAggregator
    aggr_property[:value] = 1
    aggr_json_property = JSON.generate(aggr_property)
    command <<-COMMAND
        cd "#{prefix}"
        . ./env.sh
        nefclient sysconfig setProperty '#{flush_json_property}'
        nefclient sysconfig setProperty '#{aggr_json_property}'
    COMMAND
    only_if { setagg }
    retries 3
    retry_delay 20
end

execute "performance profile" do
    command "tuned-adm profile network-latency"
    ignore_failure true
    action :nothing
    only_if { platform_family?(:rhel) }
end

execute "performance profile" do
    command <<-COMMAND
	service ondemand stop
	if test -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors; then
	    for CPUFREQ in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
	        [ -f $CPUFREQ ] || continue; echo -n performance > $CPUFREQ;
	    done
	fi
    COMMAND
    ignore_failure true
    action :nothing
    only_if { platform_family?(:debian) }
end
