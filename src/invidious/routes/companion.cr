module Invidious::Routes::Companion
  # Raised when the companion failed after response bytes were already
  # handed to the client. Deliberately not an IO::Error, so the connection
  # pool does not retry the block and write a second body.
  class StreamAborted < Exception
  end

  # GET /companion/*
  def self.get_companion(env)
    proxy(env) do |wrapper, url, headers|
      wrapper.client.get(url, headers) { |resp| proxy_companion(env, resp) }
    end
  end

  # POST /companion/*
  def self.post_companion(env)
    proxy(env) do |wrapper, url, headers|
      wrapper.client.post(url, headers, env.request.body) { |resp| proxy_companion(env, resp) }
    end
  end

  # OPTIONS /companion/*
  def self.options_companion(env)
    proxy(env) do |wrapper, url, headers|
      wrapper.client.options(url, headers) { |resp| proxy_companion(env, resp) }
    end
  end

  # Checks out a companion connection, builds the upstream URL and filtered
  # headers, and yields them. Any failure is logged and answered with 502
  # instead of an empty 200.
  private def self.proxy(env, &)
    COMPANION_POOL.client do |wrapper|
      url = Invidious::CompanionProxy.upstream_path(env.request.path, wrapper.companion.private_url)
      if query = env.request.query
        url += "?#{query}"
      end
      headers = Invidious::CompanionProxy.request_headers(env.request.headers)

      yield wrapper, url, headers
    end
  rescue ex : StreamAborted
    LOGGER.error("/companion proxy: #{ex.message}: #{ex.cause.try(&.message)}")
  rescue ex
    LOGGER.error("/companion proxy: #{ex.class}: #{ex.message}")
    bad_gateway(env)
  end

  private def self.bad_gateway(env)
    env.response.status_code = 502
    env.response.content_type = "text/plain"
    env.response.print "Invidious companion is unreachable"
  rescue
    # Headers were already sent while streaming; nothing more can be done.
  end

  private def self.proxy_companion(env, response)
    env.response.status_code = response.status_code
    response.headers.each do |key, value|
      env.response.headers[key] = value if Invidious::CompanionProxy.response_header_allowed?(key)
    end

    begin
      IO.copy response.body_io, env.response
    rescue ex
      raise StreamAborted.new("companion response aborted mid-stream", cause: ex)
    end
  end
end
