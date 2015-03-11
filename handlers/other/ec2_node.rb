#!/usr/bin/env ruby
#
# CHANGELOG:
# * 0.5.0:
#   - Adds configuration to filter by state reason
# * 0.4.0:
#   - Adds ability to specify a list of states an individual client can have in
#     EC2. If none is specified, it filters out 'terminated' and 'stopped'
#     instances by default.
#   - Updates how we are "puts"-ing to the log.
# * 0.3.0:
#   - Updates handler to additionally filter stopped instances.
# * 0.2.1:
#   - Updates requested configuration snippets so they'll be redacted by
#     default.
# * 0.2.0:
#   - Renames handler from chef_ec2_node to ec2_node
#   - Removes Chef-related stuff from handler
#   - Updates documentation
# * 0.1.0:
#   - Initial release
#
# This handler deletes a Sensu client if it's been stopped or terminated in EC2.
# Optionally, you may specify a client attribute `ec2_states`, a list of valid
# states an instance may have.
#
# You may also specify a client attribute `ec2_state_reasons`, a list of regular
# expressions to match state reasons against. This is useful if you want to fail
# on any `Client.*` state reason or on `Server.*` state reason. The default is
# to match any state reason `.*` Regardless, eventually a client will be
# deleted once AWS stops responding that the instance id exists.
#
# NOTE: The implementation for correlating Sensu clients to EC2 instances may
# need to be modified to fit your organization. The current implementation
# assumes that Sensu clients' names are the same as their instance IDs in EC2.
# If this is not the case, you can either sub-class this handler and override
# `ec2_node_should_be_deleted?` in your own organization-specific handler, or modify this
# handler to suit your needs.
#
# Requires the following Rubygems (`gem install $GEM`):
#   - sensu-plugin
#   - fog
#
# Requires a Sensu configuration snippet:
#   {
#     "aws": {
#       "access_key": "adsafdafda",
#       "secret_key": "qwuieohajladsafhj23nm",
#       "region": "us-east-1c"
#     }
#   }
#
# Or you can set the following environment variables:
#   - AWS_ACCESS_KEY_ID
#   - AWS_SECRET_ACCESS_KEY
#   - EC2_REGION
#
# If none of the settings are found it will then attempt to
# generate temporary credentials from the IAM instance profile
#
#
# To use, you can set it as the keepalive handler for a client:
#   {
#     "client": {
#       "name": "i-424242",
#       "address": "127.0.0.1",
#       "keepalive": {
#         "handler": "ec2_node"
#       },
#       "subscriptions": ["all"]
#     }
#   }
#
# You can also use this handler with a filter:
#   {
#     "filters": {
#       "ghost_nodes": {
#         "attributes": {
#           "check": {
#             "name": "keepalive",
#             "status": 2
#           },
#           "occurences": "eval: value > 2"
#         }
#       }
#     },
#     "handlers": {
#       "ec2_node": {
#         "type": "pipe",
#         "command": "/etc/sensu/handlers/ec2_node.rb",
#         "severities": ["warning","critical"],
#         "filter": "ghost_nodes"
#       }
#     }
#   }
#
# Copyleft 2013 Yet Another Clever Name
#
# Based off of the `chef_node` handler by Heavy Water Operations, LLC
#
# Released under the same terms as Sensu (the MIT license); see
# LICENSE for details

require 'timeout'
require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-handler'
require 'fog'
require 'aws-sdk'

class Ec2Node < Sensu::Handler
  def filter; end

  def handle
    # #YELLOW
    unless ec2_node_should_be_deleted? # rubocop:disable UnlessElse
      delete_sensu_client!
    else
      puts "[EC2 Node] #{@event['client']['name']} appears to exist in EC2"
    end
  end

  def delete_sensu_client!
    response = api_request(:DELETE, '/clients/' + @event['client']['name']).code
    deletion_status(response)
  end

  def ec2_node_should_be_deleted?
    states = acquire_valid_states
    state_reasons = acquire_valid_state_reasons
    filtered_instances = ec2.servers.select { |s| states.include?(s.state) && state_reasons.any?{ |reason| Regexp.new(reason) =~ s.state_reason["code"]}}
    instance_ids = filtered_instances.map(&:id)
    instance_ids.each do |id|
      return true if id == @event['client']['name']
    end
    false # no match found, node doesn't exist
  end

  def ec2
    @ec2 = get_fog_aws_instance() if @ec2.nil? || Time.now >= @expiration
  end

  def get_fog_aws_instance
    credentials = get_credentials()
    @credential_expiration = credentials["expiration"]
    Fog::Compute.new(provider: 'AWS',
        aws_access_key_id: credentials["aws_access_key_id"],
        aws_secret_access_key: credentials["aws_secret_access_key"],
        region: credentials["region"])
  end

  def get_credentials
    @credentials ||= begin
        key = settings['aws']['access_key'] || ENV['AWS_ACCESS_KEY_ID']
        secret = settings['aws']['secret_key'] || ENV['AWS_SECRET_ACCESS_KEY']
        region = settings['aws']['region'] || ENV['EC2_REGION']
        expiration = nil
        if key.nil? || key.empty? || secret.nil? || secret.empty?
            sts = AWS::STS.new()
            session = sts.new_session()
            key = session.credentials["access_key_id"]
            secret = session.credentials["secret_access_key"]
            expiration = session.expires_at
        end
        {"aws_access_key_id" => key,
            "aws_secret_access_key" => secret,
            "region" => region,
            "expiration" => expiration}
    end
  end

  def deletion_status(code)
    case code
    when '202'
      puts "[EC2 Node] 202: Successfully deleted Sensu client: #{node}"
    when '404'
      puts "[EC2 Node] 404: Unable to delete #{node}, doesn't exist!"
    when '500'
      puts "[EC2 Node] 500: Miscellaneous error when deleting #{node}"
    else
      puts "[EC2 Node] #{res}: Completely unsure of what happened!"
    end
  end

  def acquire_valid_states
    if @event['client'].key?('ec2_states')
      return @event['client']['ec2_states']
    else
      return ['running']
    end
  end

  def acquire_valid_state_reasons
    if @event['client'].key?('ec2_state_reasons')
      return @event['client']['ec2_state_reasons']
    else
      return ['.*']
    end
  end
end
