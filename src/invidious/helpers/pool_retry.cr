# Retry policy for requests made on a pooled, keep-alive HTTP connection.
module Invidious::PoolRetry
  extend self

  # A transport failure means the connection itself broke, so the request
  # never reached a peer that could act on it: the peer closed a pooled
  # connection while it sat idle, the socket was reset, or TLS failed.
  #
  # Two kinds of failure are deliberately *not* transport failures, because
  # in both the peer did get the request:
  #
  #   * an application error (an unexpected status code, unparsable JSON,
  #     ...) - the peer answered, and must not be asked twice;
  #   * a read timeout - the peer accepted the request and may still be
  #     working on it. The socket is alive, so reconnecting recovers
  #     nothing; it only throws away the work already in flight and makes a
  #     slow peer do it a second time while the user waits out a second
  #     timeout. `IO::TimeoutError` is an `IO::Error`, so it has to be
  #     excluded explicitly.
  def transport_failure?(ex : Exception) : Bool
    return false if ex.is_a?(IO::TimeoutError)

    ex.is_a?(IO::Error) || ex.is_a?(OpenSSL::Error)
  end

  # Runs the given block, retrying it exactly once when the first attempt
  # fails with a transport failure.
  #
  # Only a broken connection is retried; see `transport_failure?` for what
  # does not qualify.
  #
  # `reconnect` runs before the retry and must drop the broken socket of the
  # connection the caller holds, so that the second attempt opens a fresh
  # one. Retrying on a *different* connection taken from the pool instead
  # does not recover: connections that entered the pool during the same idle
  # period are closed by the peer at the same time, so the replacement is as
  # likely to be dead as the connection that just failed.
  #
  # Only requests that are safe to send twice may be wrapped: the peer may
  # have received and processed the first attempt before closing.
  def with_reconnect(reconnect : Proc(Nil), & : -> T) : T forall T
    yield
  rescue ex
    raise ex unless transport_failure?(ex)
    reconnect.call
    yield
  end
end
