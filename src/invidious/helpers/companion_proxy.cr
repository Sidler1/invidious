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
    "server",
    "set-cookie",
    "strict-transport-security",
    "transfer-encoding",
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

  # Maps the public `/companion/...` path onto the companion's configured
  # base path (`private_url.path`), mirroring what `_post_invidious_companion`
  # does for the player request.
  def upstream_path(request_path : String, private_url : URI) : String
    base = private_url.path.rchop("/")
    base + request_path.lchop("/companion")
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
