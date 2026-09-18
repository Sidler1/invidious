# Header and path handling for the built-in `/companion/*` reverse proxy
# (`routes/companion.cr`). Kept separate so it can be unit-tested.
module Invidious::CompanionProxy
  extend self

  # Request headers the browser may pass through to the companion. Everything
  # else, in particular `Cookie` (carries the Invidious session id),
  # `Authorization` and `Host`, is dropped so it never leaves this process.
  REQUEST_HEADERS_ALLOWLIST = {
    "accept",
    "accept-encoding",
    "accept-language",
    "cache-control",
    "content-length",
    "content-type",
    "if-modified-since",
    "if-none-match",
    "origin",
    "range",
  }

  # Response headers that must not be copied back to the browser: hop-by-hop
  # headers and anything that would override the security headers Invidious
  # sets in `before_all`.
  RESPONSE_HEADERS_DENYLIST = {
    "alt-svc",
    "connection",
    "content-security-policy",
    "keep-alive",
    "proxy-authenticate",
    "server",
    "set-cookie",
    "strict-transport-security",
    "te",
    "trailer",
    "transfer-encoding",
    "upgrade",
    "x-frame-options",
  }

  def request_headers(incoming : HTTP::Headers) : HTTP::Headers
    headers = HTTP::Headers.new
    incoming.each do |name, values|
      headers[name] = values if REQUEST_HEADERS_ALLOWLIST.includes?(name.downcase)
    end
    headers
  end

  def response_header_allowed?(name : String) : Bool
    !RESPONSE_HEADERS_DENYLIST.includes?(name.downcase)
  end

  # True when the failure is the browser going away (seek, pause, closed
  # tab): `HTTP::Server::Response` raises `ClientError` when it cannot write
  # to the client, and the proxy wraps that in `StreamAborted`. Such aborts
  # are routine and must not be logged as errors.
  def client_disconnect?(ex : Exception) : Bool
    current : Exception? = ex
    while current
      return true if current.is_a?(HTTP::Server::ClientError)
      current = current.cause
    end
    false
  end

  # Maps the public `/companion/...` path onto the companion's configured
  # base path (`private_url.path`), mirroring what `_post_invidious_companion`
  # does for the player request.
  def upstream_path(request_path : String, private_url : URI) : String
    base = private_url.path.rchop("/")
    base + request_path.lchop("/companion")
  end

  # Browser-facing URL for one caption track. `base` is the companion's
  # `public_url` when one is configured (the companion serves
  # `/api/v1/captions` itself) and `""` when Invidious serves the track;
  # `check` is the signed token the companion requires, `nil` without one.
  #
  # `label` is YouTube-sourced free text and must be percent-encoded: a
  # track named with an "&" or a "#" would otherwise cut the query short,
  # and the companion compares the decoded value with the real track name,
  # so that track answers 404. Invidious' own `/api/v1/captions` listing
  # already encodes the same value. The caller still has to HTML-escape the
  # result before putting it in an attribute.
  def caption_track_url(base : String, video_id : String, label : String, check : String?) : String
    url = "#{base}/api/v1/captions/#{video_id}?label=#{URI.encode_www_form(label)}"
    url += "&check=#{check}" if check
    url
  end

  # Builds the browser-facing companion URL for a legacy stream/manifest
  # redirect: the original query minus any client-supplied `check`, plus a
  # freshly minted `check` token for `video_id`.
  def stream_redirect(public_url : URI, path : String, query : URI::Params, video_id : String) : String
    params = URI::Params.parse(query.to_s)
    params.delete_all("check")
    params["check"] = invidious_companion_encrypt(video_id)
    "#{public_url}#{path}?#{params}"
  end
end
