#!/usr/bin/env ruby
#
# Sensu Handler: hipchat
#
# This handler script is used to send notifications to Hipchat rooms.
#
# Input:
#   @event - Event attributes.
#      @event['action'] - Property to figure out the event type i.e. whether it is create or resolve.
#      @event['check'] - Map of attributes from the check config which is calling this handler
#      @event['client'] - Map of attributes from the client config for the clients from which this event is generated.
#   option: json_config - By default, assumes the hipchat config parameters are in a file called "hipchat.json" with
#                         "hipchat" being the top-level key of the json. This command line option allows to specify
#                         a custom file instead of "hipchat.json" to fetch the hipchat config from.
#
# Output:
#    Green coloured notification on the Hipchat room if a resolve event is seen.
#    Yellow coloured notification used to notify warning if a create event is seen with a status of 1
#    Red coloured notification used to notify critical if a create event is seen with a status other than 1
#
# Note: The default hipchat config is fetched from the predefined json config file which is "hipchat.json" or any other
#       file defiend using the "json_config" command line option. The hipchat room could also be configured on a per client basis
#       by defining the "hipchat_room" attribute in the client config file. This will override the default hipchat room where the
#       alerts are being routed to for that particular client.

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-handler'
require 'hipchat'
require 'timeout'
require 'net/http'
require 'securerandom'
require 'aws-sdk'

class HipChatNotif < Sensu::Handler
  option :json_config,
         description: 'Config Name',
         short: '-j JsonConfig',
         long: '--json_config JsonConfig',
         required: false

  def get_target
    @event['check']['command'].split('"')[1].tr('"', "").delete(' ')
  end

  def get_warning
    @event['check']['command'].split("-w ")[1].split('"')[1].delete('"')
  end

  def get_critical
    @event['check']['command'].split("-c ")[1].split('"')[1].delete('"')
  end

  def get_window
    @event['check']['command'].split("-i ")[1].split(" ")[0]
  end

  def get_method
    @event['check']['command'].split("-m ")[1].split(" ")[0]
  end

  def alert_duration
        seconds = @event['occurrences'] * @event['check']['interval']
        Time.at(seconds).utc.strftime("%H:%M:%S")
  end

  def convert_to_list(list)
    if list.is_a?(Array)
       return list
    else
       return Array(list)
    end
  end

  def parse_alert_codes(hipchat_mode)
        codes = Array[]
        if not @event['check']['status'] == 0
        @event['check']['output'].split(' ').each do |item|
                 if item =~ /^\(\w\)$/
                    codes << item.delete(')').delete('(')
                 end
             end
        else
              codes << 'R'
        end
        return codes.join('|')
  end

  def parse_alert_values(hipchat_mode)
        values = Array[]
        if not @event['check']['status'] == 0
           @event['check']['output'].split(' ').each do |item|
               if item =~ /^(\d.*)$|^(\-\d.*)$/
                   values << item.delete(',')
               end
           end
        else
               values << 'OK'
        end
        return values.join('|')
  end

  def uchiwa_alert_url(uchiwa_url_public)
     return "#{uchiwa_url_public}/#/client/Sensu/#{@event['client']['name']}?check=#{@event['check']['name']}"
  end

  def img_include(s3_public_url, graphite_url_public)
     return "<a href=\"#{prepare_img_url(graphite_url_public)}\"><img src=\"#{s3_public_url}\" alt=\"#{s3_public_url}\"></a>"
  end

  def link_footer(uchiwa_url_public, graphite_url_public)
      return "<b><a href=\"#{uchiwa_alert_url(uchiwa_url_public)}\">Uchiwa </a><a href=\"#{prepare_img_url(graphite_url_public)}\">Graphite</a></b>"
  end

  def minimal_template(alert_level, hipchat_mode, uchiwa_url_public, graphite_url_public)
      return "<table><tr><td><b>#{alert_level.upcase}</b> #{@event['client']['name']} :: #{@event['check']['name']} :: #{get_target} :: #{parse_alert_codes(hipchat_mode)} :: #{parse_alert_values(hipchat_mode)} :: W:#{get_warning}|C:#{get_critical} :: #{link_footer(uchiwa_url_public, graphite_url_public)} :: #{alert_duration}</td></tr></table>"
  end

  def normal_template(alert_level, hipchat_mode, uchiwa_url_public, graphite_url_public, s3_public_url)
     return "<table><tr><td>#{img_include(s3_public_url, graphite_url_public)}</td></tr><tr><td><b>#{alert_level.upcase}</b> #{@event['client']['name']} :: #{@event['check']['name']} :: #{get_target} :: #{parse_alert_codes(hipchat_mode)} :: #{parse_alert_values(hipchat_mode)} :: W:#{get_warning}|C:#{get_critical} :: #{link_footer(uchiwa_url_public, graphite_url_public)} :: #{alert_duration}</td></tr></table>"
  end

  def full_template(alert_level, hipchat_mode, uchiwa_url_public, graphite_url_public, s3_public_url)
     return "<table><tr><td>#{img_include(s3_public_url, graphite_url_public)}</td></tr><tr><td><b>#{alert_level.upcase}</b> #{@event['client']['name']} :: #{@event['check']['name']} :: #{get_target} :: #{parse_alert_codes(hipchat_mode)} :: #{parse_alert_values(hipchat_mode)} :: W:#{get_warning}|C:#{get_critical} :: [o: #{@event['occurrences']}, i: #{@event['check']['interval']}, r: #{@event['check']['refresh']} m: #{get_method}] :: #{link_footer(uchiwa_url_public, graphite_url_public)} :: #{alert_duration}</td></tr></table>"
  end

  def prepare_img_url(graphite_url_public)
      return "#{graphite_url_public}/render?target=#{get_target}&format=png&width=900&height=400&from=-#{get_window}&bgcolor=ffffff&fgcolor=000000&areaAlpha=0.1&lineWidth=2&hideLegend=False&drawNullAsZero=False&fontSize=8&areaMode=all&target=aliasSub(constantLine(#{get_warning}),'^.*',%20'Warning')&target=aliasSub(constantLine(#{get_critical}),'^.*',%20'Critical')"
  end

  def get_png(graphite_url_private)
       body =
      begin
        # prepare graphite private api url with no auth to render image
        uri_prep = "#{graphite_url_private}/render?target=#{get_target}&format=png&width=400&height=200&from=-#{get_window}&bgcolor=ffffff&fgcolor=000000&areaAlpha=0.1&lineWidth=1&hideLegend=true&drawNullAsZero=False&target=aliasSub(constantLine(#{get_warning}),'^.*',%20'Warning')&target=aliasSub(constantLine(#{get_critical}),'^.*',%20'Critical')&fontSize=8&areaMode=all"
        uri = URI(uri_prep)
        res = Net::HTTP.get_response(uri)
        res.body
      rescue => e
        puts "Failed to query graphite: #{e.inspect}"
      end
  end

  def msg_mode(hipchat_mode, level, graphite_url_public, s3_public_url, uchiwa_url_public, message)
      if hipchat_mode.eql?('full')
               msg = "#{full_template(level, hipchat_mode, uchiwa_url_public, graphite_url_public, s3_public_url)}"
      elsif hipchat_mode.eql?('normal')
               msg = "#{normal_template(level, hipchat_mode, uchiwa_url_public, graphite_url_public, s3_public_url)}"
      elsif hipchat_mode.eql?('minimal')
               msg = "#{minimal_template(level, hipchat_mode, uchiwa_url_public, graphite_url_public)}"
      end
      return msg
  end

  def handle
    json_config = config[:json_config] || 'hipchat'
    server_url = settings[json_config]['server_url'] || 'https://api.hipchat.com'
    apiversion = settings[json_config]['apiversion'] || 'v1'
    proxy_url = settings[json_config]['proxy_url']
    hipchatmsg = HipChat::Client.new(settings[json_config]['apikey'], api_version: apiversion, http_proxy: proxy_url, server_url: server_url)
    hipchat_rooms = @event['check']['hipchat_room'] || settings[json_config]['room']
    hipchat_mode = @event['check']['hipchat_mode'] || "normal"
    rooms = convert_to_list(hipchat_rooms)
    from = @event['check']['hipchat_msgname'] || settings[json_config]['from'] || 'Sensu'
    s3_access_key_id = settings[json_config]['s3_key']
    s3_secret_access_key = settings[json_config]['s3_secret']
    s3_bucket_region = settings[json_config]['s3_bucket_region']
    graphite_url_private = settings[json_config]['graphite_endpoint_private']
    graphite_url_public = settings[json_config]['graphite_endpoint_public']
    uchiwa_url_public = settings[json_config]['uchiwa_endpoint_public']

    #message = @event['check']['notification'] || @event['check']['output']
    message = @event['check']['output']

    # If the playbook attribute exists and is a URL, "[<a href='url'>playbook</a>]" will be output.
    # To control the link name, set the playbook value to the HTML output you would like.
    if @event['check']['playbook']
      begin
        uri = URI.parse(@event['check']['playbook'])
        if %w( http https ).include?(uri.scheme)
          message << "  [<a href='#{@event['check']['playbook']}'>Playbook</a>]"
        else
          message << "  Playbook:  #{@event['check']['playbook']}"
        end
      rescue
        message << "  Playbook:  #{@event['check']['playbook']}"
      end
    end


       for room in rooms
            begin
              timeout(3) do
                  # add s3 images upload based on graphite rendered png
                  current_time = Time.now
                  s3 = Aws::S3::Resource.new(credentials: Aws::Credentials.new(s3_access_key_id, s3_secret_access_key), region: s3_bucket_region)
                  obj = s3.bucket('sensu-hipchat-images').object(current_time.strftime("%d-%m-%Y") + "/" + current_time.strftime("%H/%M") + "/" + SecureRandom.hex(25) + '.png')
                  obj.put(body:get_png(graphite_url_private), acl:'public-read', storage_class:'REDUCED_REDUNDANCY')
                  s3_public_url = obj.public_url
                  # send one message in html format contains images to all types of alert
                if @event['action'].eql?('resolve')
                  hipchatmsg[room].send(from, msg_mode(hipchat_mode, 'resolved', graphite_url_public, s3_public_url, uchiwa_url_public, message), color: 'green')
                  puts "hipchat -- sent resolved for #{@event['client']['name']} / #{@event['check']['name']} to #{room}"
                else
                  hipchatmsg[room].send(from, msg_mode(hipchat_mode, @event['check']['status'] == 1 ? 'warning' : 'critical', graphite_url_public, s3_public_url, uchiwa_url_public, message), color: @event['check']['status'] == 1 ? 'yellow' : 'red', notify: true)
                  puts "hipchat -- sent #{@event['check']['status'] == 1 ? 'warning' : 'critical'} for #{@event['client']['name']} / #{@event['check']['name']} to #{room}"
                end
              end
            rescue Timeout::Error
              puts "hipchat -- timed out while attempting to message #{room}"
            end
       end
end
end
