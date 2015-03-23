#! /usr/bin/env ruby
#
#   check-consul-leader
#
# DESCRIPTION:
#   This plugin checks if consul is up and reachable. It then checks
#   the status/leader and ensures there is a current leader.
#
# OUTPUT:
#   plain text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: sensu-plugin
#   gem: rest-client
#   gem: rubysl-resolv
#
# USAGE:
#   #YELLOW
#
# NOTES:
#
# LICENSE:
#   Copyright 2015 Sonian, Inc. and contributors. <support@sensuapp.org>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#
#
# Consul returns the numerical values for consul members state, which the
# numbers used are defined in : https://github.com/hashicorp/serf/blob/master/serf/serf.go
#
# StatusNone MemberStatus = iota  (0, "none")
# StatusAlive                     (1, "alive")
# StatusLeaving                   (2, "leaving")
# StatusLeft                      (3, "left")
# StatusFailed                    (4, "failed")
#

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-plugin/check/cli'
require 'rest-client'

class ConsulStatus < Sensu::Plugin::Check::CLI

  def run
    r = RestClient::Resource.new("http://#{settings[:consul][:host]}:#{settings[:consul][:port]}/v1/agent/members", timeout: 5).get
    if r.code == 200
        failing_nodes = JSON.parse(r).find{|node| node["Status"] == 4}
        if failing_nodes != nil && !failing_nodes.empty?
            critical 'Failed nodes exist within the consul cluster!'
        end
    else
      critical 'Consul is not responding'
    end
  rescue Errno::ECONNREFUSED
    critical 'Consul is not responding'
  rescue RestClient::RequestTimeout
    critical 'Consul Connection timed out'
  end
end
