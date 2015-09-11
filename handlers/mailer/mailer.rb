#!/usr/bin/env ruby
#
# Sensu Handler: mailer
#
# This handler formats alerts as mails and sends them off to a pre-defined recipient.
#
# Copyright 2012 Pal-Kristian Hamre (https://github.com/pkhamre | http://twitter.com/pkhamre)
#
# Released under the same terms as Sensu (the MIT license); see LICENSE
# for details.

# Note: The default mailer config is fetched from the predefined json config file which is "mailer.json" or any other
#       file defiend using the "json_config" command line option. The mailing list could also be configured on a per client basis
#       by defining the "mail_to" attribute in the client config file. This will override the default mailing list where the
#       alerts are being routed to for that particular client.

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-handler'
require 'mail'
require 'timeout'
require 'net/http'
require 'securerandom'
require 'aws-sdk'
require 'erubis'

# patch to fix Exim delivery_method: https://github.com/mikel/mail/pull/546
# #YELLOW
module ::Mail # rubocop:disable Style/ClassAndModuleChildren
  class Exim < Sendmail
    def self.call(path, arguments, _destinations, encoded_message)
      popen "#{path} #{arguments}" do |io|
        io.puts encoded_message.to_lf
        io.flush
      end
    end
  end
end

class Mailer < Sensu::Handler
  option :json_config,
         description: 'Config Name',
         short: '-j JsonConfig',
         long: '--json_config JsonConfig',
         required: false

  def short_name
    @event['client']['name'] + '/' + @event['check']['name']
  end

  def action_to_string
    @event['action'].eql?('resolve') ? 'RESOLVED' : 'ALERT'
  end

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

  def get_warning_parsed
   if get_warning.match(" ") then
      return get_warning.split(" ")[1]
    else
      return get_warning
    end
  end

  def get_critical_parsed
    if get_critical.match(" ") then
       return get_critical.split(" ")[1]
    else
       return get_critical
    end
  end

  def alert_duration
        seconds = @event['occurrences'] * @event['check']['interval']
        Time.at(seconds).utc.strftime("%H:%M:%S")
  end

  def admin_alert_url(admin_gui)
     return "#{admin_gui}/#/client/Sensu/#{@event['client']['name']}?check=#{@event['check']['name']}"
  end

  def parsed_check_name
      if @event['check']['name']
         return @event['check']['name'].gsub(/(\_|\.)/,' ')
      else
         return @event['check']['name']
      end
  end

  def parsed_source_name
      if @event['check']['source']
         return @event['check']['source'].gsub(/(\_|\.)/,' ')
      else
         return @event['check']['source']
      end
  end

  def status_to_string
    case @event['check']['status']
    when 0
      return 'OK'
    when 1
      return 'WARNING'
    when 2
      return 'CRITICAL'
    else
      return 'UNKNOWN'
    end
  end

  def bgcolor
   case @event['check']['status']
    when 0
      return '#E1F1E8'
    when 1
      return '#FEFEEE'
    when 2
      return '#F5E1E1'
    else
      return '#E5E5E5'
    end
  end

  def build_mail_to_list
    json_config = config[:json_config] || 'mailer'
    mail_to = @event['check']['mail_to'] || settings[json_config]['mail_to']
    if settings[json_config].key?('subscriptions')
      @event['check']['subscribers'].each do |sub|
        if settings[json_config]['subscriptions'].key?(sub)
          mail_to << ", #{settings[json_config]['subscriptions'][sub]['mail_to']}"
        end
      end
    end
    mail_to
  end

  def get_png(graphite_url_private)
       body =
      begin
        # prepare graphite private api url with no auth to render image
        uri_prep = "#{graphite_url_private}/render?target=#{get_target}&format=png&width=400&height=200&from=-#{get_window}&bgcolor=ffffff&fgcolor=000000&areaAlpha=0.1&lineWidth=1&hideLegend=true&drawNullAsZero=False&target=aliasSub(constantLine(#{get_warning_parsed}),'^.*',%20'Warning')&target=aliasSub(constantLine(#{get_critical_parsed}),'^.*',%20'Critical')&fontSize=8&areaMode=all"
        uri = URI(uri_prep)
        res = Net::HTTP.get_response(uri)
        res.body
      rescue => e
        puts "Failed to query graphite: #{e.inspect}"
      end
  end

  def uchiwa_alert_url(uchiwa_url_public)
     return "#{uchiwa_url_public}/#/client/Sensu/#{@event['client']['name']}?check=#{@event['check']['name']}"
  end

  def prepare_img_url(graphite_url_public)
      return "#{graphite_url_public}/render?target=#{get_target}&format=png&width=900&height=400&from=-#{get_window}&bgcolor=ffffff&fgcolor=000000&areaAlpha=0.1&lineWidth=2&hideLegend=False&drawNullAsZero=False&fontSize=8&areaMode=all&target=aliasSub(constantLine(#{get_warning_parsed}),'^.*',%20'Warning')&target=aliasSub(constantLine(#{get_critical_parsed}),'^.*',%20'Critical')"
  end

  def img_include(s3_public_url, graphite_url_public)
     return "<a href=\"#{prepare_img_url(graphite_url_public)}\"><img src=\"#{s3_public_url}\" alt=\"#{s3_public_url}\"></a>"
  end

  def link_footer(uchiwa_url_public, graphite_url_public)
      return "<b><a href=\"#{uchiwa_alert_url(uchiwa_url_public)}\">Uchiwa </a><a href=\"#{prepare_img_url(graphite_url_public)}\">Graphite</a></b>"
  end

  def s3_public_img
    # add s3 images upload based on graphite rendered png
    current_time = Time.now
    s3 = Aws::S3::Resource.new(credentials: Aws::Credentials.new(s3_access_key_id, s3_secret_access_key), region: s3_bucket_region)
    obj = s3.bucket('sensu-images').object(current_time.strftime("%d-%m-%Y") + "/" + current_time.strftime("%H/%M") + "/" + "mailer" + SecureRandom.hex(25) + '.png')
    obj.put(body:get_png(graphite_url_private), acl:'public-read', storage_class:'REDUCED_REDUNDANCY')
    s3_public_url = obj.public_url
  end

  def subject_default_template
      if @event['check']['source'] and @event['check']['notification']
         return "<%=status%> | <%=check_name%> | <%=source_name%> :: #{@event['check']['notification']}"
      elsif @event['check']['source'] and @event['check']['notification'].nil?
         return "<%=status%> | <%=check_name%> | <%=source_name%>"
      else
         return "<%=status%> | <%=check_name%>"
      end
  end

  def plain_body_default_template
      return "Name: <%=check['name']%>\n
              Uchiwa: <%=alertui%>\n
              Host: <%=client['name']%>\n
              Timestamp: <%=time%>\n
              Address: <%=client['address']%>\n
              Status: <%=status%>\n
              Occurrences: <%=occurrences]%>\n
              Duration: <%=duration}%>\n
              Playbook: <%=playbook%>\n\n\n
              Command: <%=nopasscommand%>\n
              Check_output: <%=nopasscheckout%>"
  end

  def html_body_default_template
    return "<html><body><table bgcolor=<%=bgcolor%>><tr><td>
            <h2><%=status%> for <%=check_name%></h2>
            <p><%=imginclude%></p>
            <p><b>Name: </b><%=check['name']%><br /> <b>Warning/Critical Level:</b> <%=warning%> / <%=critical%><br /><b>Target: </b> <%=target%><br /> <b>AlertUI: </b><%=alertui%><br /> <b>Source: </b><%=check['source']%><br /> <b>Timestamp: </b><%=time%><br /> <b>Duration: </b><%=duration%><br /> <b>Check_output: </b><%=nopasscheckout%></p>
            </td></tr></table></body></html>"
  end

  def handle
    json_config = config[:json_config] || 'mailer'
    admin_gui = settings[json_config]['admin_gui'] || 'http://localhost:8080/'
    mail_to = build_mail_to_list
    mail_from =  settings[json_config]['mail_from']
    reply_to = settings[json_config]['reply_to'] || mail_from

    delivery_method = settings[json_config]['delivery_method'] || 'smtp'
    smtp_address = settings[json_config]['smtp_address'] || 'localhost'
    smtp_port = settings[json_config]['smtp_port'] || '25'
    smtp_domain = settings[json_config]['smtp_domain'] || 'localhost.localdomain'

    smtp_username = settings[json_config]['smtp_username'] || nil
    smtp_password = settings[json_config]['smtp_password'] || nil
    smtp_authentication = settings[json_config]['smtp_authentication'] || :plain
    smtp_enable_starttls_auto = settings[json_config]['smtp_enable_starttls_auto'] == 'false' ? false : true

    s3_access_key_id = settings[json_config]['s3_key'] || nil
    s3_secret_access_key = settings[json_config]['s3_secret'] || nil
    s3_bucket = settings[json_config]['s3_bucket'] || nil
    s3_bucket_region = settings[json_config]['s3_bucket_region'] || nil
    graphite_url_private = settings[json_config]['graphite_endpoint_private'] || nil
    graphite_url_public = settings[json_config]['graphite_endpoint_public'] || nil
    uchiwa_url_public = settings[json_config]['uchiwa_endpoint_public'] || nil

    # try to redact passwords from output and command
    output = "#{@event['check']['output']}".gsub(/(-p|-P|--password)\s*\S+/, '\1 <password redacted>')
    command = "#{@event['check']['command']}".gsub(/(-p|-P|--password)\s*\S+/, '\1 <password redacted>')
    playbook = "Playbook:  #{@event['check']['playbook']}" if @event['check']['playbook']

    # add s3 images upload based on graphite rendered png
    current_time = Time.now
    s3 = Aws::S3::Resource.new(credentials: Aws::Credentials.new(s3_access_key_id, s3_secret_access_key), region: s3_bucket_region)
    obj = s3.bucket(s3_bucket).object(current_time.strftime("%d-%m-%Y") + "/" + current_time.strftime("%H/%M") + "/" + SecureRandom.hex(25) + '.png')
    obj.put(body:get_png(graphite_url_private), acl:'public-read', storage_class:'REDUCED_REDUNDANCY')
    s3_public_url = obj.public_url

      erbvalues = { }
    # template values for ERB based on event check data
      erbvalues[:check] = @event['check']
      erbvalues[:client] = @event['client']
    # adding custom values
      erbvalues[:id] = "#{@event['id']}" || nil
      erbvalues[:check_name] = "#{parsed_check_name}" || nil
      erbvalues[:source_name] = "#{parsed_source_name}" || nil
      erbvalues[:occurrences] = "#{@event['occurrences']}" || nil
      erbvalues[:action] = "#{@event['action']}" || nil
      erbvalues[:alertui] = "#{uchiwa_alert_url(uchiwa_url_public)}" || nil
      erbvalues[:time] = "#{Time.at(@event['check']['issued'])}" || nil
      erbvalues[:status] = "#{status_to_string}" || nil
      erbvalues[:duration] = "#{alert_duration}" || nil
      erbvalues[:nopasscommand] = "#{command}" || nil
      erbvalues[:nopasscheckout] = "#{output}" || nil
      erbvalues[:playbook] = "#{playbook}" || nil
      erbvalues[:target] = "#{get_target}" || nil
      erbvalues[:warning] = "#{get_warning}" || nil
      erbvalues[:critical] = "#{get_critical}" || nil
      erbvalues[:imgurl] = "#{prepare_img_url(graphite_url_public)}" || nil
      erbvalues[:imginclude] = "#{img_include(s3_public_url, graphite_url_public)}" || nil
      erbvalues[:linkfooter] = "#{link_footer(uchiwa_url_public, graphite_url_public)}" || nil
      erbvalues[:bgcolor] = "#{bgcolor}" || nil

    if @event['check']['mail_mode'] == "plain"
        content_type = 'text/plain; charset=UTF-8'
#        body = <<-BODY.gsub(/^\s+/, '')
#                Name: #{@event['check']['name']}
#                Uchiwa: #{admin_alert_url(admin_gui)}
#                Host: #{@event['client']['name']}
#                Timestamp: #{Time.at(@event['check']['issued'])}
#                Address:  #{@event['client']['address']}
#                Status:  #{status_to_string}
#                Occurrences:  #{@event['occurrences']}
#                Duration: #{alert_duration}
#                Command:  #{command}
#                Check_output: #{output}
#                #{playbook}
#             BODY
        if @event['check']['mail_body']
           body = Erubis::Eruby.new(@event['check']['mail_body']).result(erbvalues)
        else
           body = Erubis::Eruby.new("#{plain_body_default_template}").result(erbvalues)
        end
    elsif @event['check']['mail_mode'] == "html"
        content_type = 'text/html; charset=UTF-8'
        if @event['check']['mail_body']
           body = Erubis::Eruby.new(@event['check']['mail_body']).result(erbvalues)
        else
           body = Erubis::Eruby.new("#{html_body_default_template}").result(erbvalues)
        end
    end

    if @event['check']['mail_subject']
       subject = Erubis::Eruby.new("#{@event['check']['mail_subject']}").result(erbvalues)
    else
       subject = Erubis::Eruby.new("#{subject_default_template}").result(erbvalues)
    end

    Mail.defaults do
      delivery_options = {
        address: smtp_address,
        port: smtp_port,
        domain: smtp_domain,
        openssl_verify_mode: 'none',
        enable_starttls_auto: smtp_enable_starttls_auto
      }

      unless smtp_username.nil?
        auth_options = {
          user_name: smtp_username,
          password: smtp_password,
          authentication: smtp_authentication
        }
        delivery_options.merge! auth_options
      end

      delivery_method delivery_method.intern, delivery_options
    end

    begin
      timeout 10 do
        Mail.deliver do
          to mail_to
          from mail_from
          reply_to reply_to
          subject subject
          content_type content_type
          body body
        end

        puts 'mail -- sent alert for ' + short_name + ' to ' + mail_to.to_s
      end
    rescue Timeout::Error
      puts 'mail -- timed out while attempting to ' + @event['action'] + ' an incident -- ' + short_name
    end
  end
end
