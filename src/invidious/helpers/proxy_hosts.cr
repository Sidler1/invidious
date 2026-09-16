# Host allow-lists for the media proxies (`/videoplayback`, `/sb`, ...).
#
# Every function here only ever sees attacker-controlled strings, so the
# patterns are anchored and refuse userinfo, ports and paths outright.
# `URI.parse("https://x.googlevideo.com@10.0.0.5")` yields host `10.0.0.5`,
# which is why a substring match is not enough.
module Invidious::ProxyHosts
  extend self

  GOOGLEVIDEO_HOST = /\A[a-z0-9-]+\.(?:googlevideo|c\.youtube)\.com\z/
  YTIMG_SUBDOMAIN  = /\A[a-z][a-z0-9]{0,7}\z/

  def valid_googlevideo_host?(host : String) : Bool
    GOOGLEVIDEO_HOST.matches?(host)
  end

  # A redirect target returned by a googlevideo host must itself be an
  # allow-listed https host without userinfo or an explicit port.
  def valid_googlevideo_redirect?(location : URI) : Bool
    host = location.host
    return false if host.nil?
    return false unless location.scheme == "https"
    return false unless location.user.nil? && location.port.nil?
    valid_googlevideo_host?(host)
  end

  def valid_ytimg_subdomain?(subdomain : String) : Bool
    YTIMG_SUBDOMAIN.matches?(subdomain)
  end
end
