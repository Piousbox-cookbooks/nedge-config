#
# Cookbook Name:: nedge-config
# Recipe:: repo
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

if node[:nedge_repo]
    uri = node[:nedge_repo][:uri]
end

if uri == nil
    uri = {
        :debian => "http://apt.nexenta.com/nedge/ubuntu14",
        :rhel => "http://apt.nexenta.com/nedge/rhel7"
    }
end

if platform_family?(:debian)
    include_recipe "apt"
    apt_repository 'nedge' do
        uri             uri[:debian]
        arch            "amd64"
        distribution    node[:lsb][:codename]
        components      [:main]
    end
end

if platform_family?(:rhel)
    include_recipe "yum"
    yum_repository 'nedge' do
        baseurl         node[:nedge_repo][:uri][:rhel] + "/$basearch/"
        gpgcheck        false
        action          :add
    end
end

execute "apt-get-update" do
  command "apt-get update"
  ignore_failure true
  action :nothing
  only_if { platform_family?(:debian) }
end
