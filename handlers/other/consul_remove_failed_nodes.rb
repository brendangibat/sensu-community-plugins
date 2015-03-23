#!/usr/bin/env ruby
#

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-plugin/check/cli'
require 'rest-client'

class ConsulRemoveFailedNodes < Sensu::Handler
  def filter; end

  def handle
    r = RestClient::Resource.new("http://#{settings[:consul][:host]}:#{settings[:consul][:port]}/v1/agent/members", timeout: 5).get
    if r.code == 200
      failing_nodes = JSON.parse(r).find_all{|node| node["Status"] == 4}
      if failing_nodes != nil && !failing_nodes.empty?
          failing_nodes.each_entry{|node| RestClient::Resource.new("http://#{settings[:consul][:host]}:#{settings[:consul][:port]}/v1/agent/force-leave/#{node["Name"]}", timeout: 5)}
      end
    else
        critical 'Consul is not responding'
    end
  end
end
