require "../spec_helper"

# Models a pooled keep-alive connection: it is "stale" when the peer closed
# it while it sat idle in the pool. A stale connection fails the first read
# with the exact error Crystal's HTTP::Client raises in that case, and only
# a reconnect (`close`, which drops the dead socket) makes it usable again.
private class StaleConnection
  getter attempts = 0

  def initialize(@stale : Bool)
  end

  def request : String
    @attempts += 1
    raise IO::EOFError.new("Unexpected end of http response") if @stale
    "response"
  end

  def close : Nil
    @stale = false
  end
end

private class AppError < Exception
end

Spectator.describe "Invidious::PoolRetry.transport_failure?" do
  it "is true for the EOF raised on a connection the peer closed" do
    ex = IO::EOFError.new("Unexpected end of http response")
    expect(Invidious::PoolRetry.transport_failure?(ex)).to be_true
  end

  it "is true for a generic IO error" do
    expect(Invidious::PoolRetry.transport_failure?(IO::Error.new("broken pipe"))).to be_true
  end

  it "is false for an application error" do
    expect(Invidious::PoolRetry.transport_failure?(AppError.new("non 200"))).to be_false
  end
end

Spectator.describe "Invidious::PoolRetry.with_reconnect" do
  it "does not reconnect when the first attempt succeeds" do
    conn = StaleConnection.new(stale: false)
    reconnects = 0

    result = Invidious::PoolRetry.with_reconnect(->{ reconnects += 1; nil }) { conn.request }

    expect(result).to eq("response")
    expect(conn.attempts).to eq(1)
    expect(reconnects).to eq(0)
  end

  # The regression this fixes: every connection that entered the pool during
  # the same idle period is closed by the peer at the same time, so retrying
  # on a *different* pooled connection hits a second dead socket and the
  # EOFError reaches the user as a 500. Reconnecting the connection we
  # already hold is what makes the retry actually recover.
  it "reconnects the held connection and succeeds on the retry" do
    conn = StaleConnection.new(stale: true)

    result = Invidious::PoolRetry.with_reconnect(->{ conn.close }) { conn.request }

    expect(result).to eq("response")
    expect(conn.attempts).to eq(2)
  end

  it "retries a stale connection exactly once" do
    conn = StaleConnection.new(stale: true)
    reconnects = 0

    Invidious::PoolRetry.with_reconnect(->{ reconnects += 1; conn.close }) { conn.request }

    expect(reconnects).to eq(1)
  end

  it "propagates the error when the retry fails as well" do
    conn = StaleConnection.new(stale: true)

    expect do
      # A reconnect that does not clear the failure, e.g. the peer is down.
      Invidious::PoolRetry.with_reconnect(->{ nil }) { conn.request }
    end.to raise_error(IO::EOFError)

    expect(conn.attempts).to eq(2)
  end

  it "never retries an application error" do
    reconnects = 0

    expect do
      Invidious::PoolRetry.with_reconnect(->{ reconnects += 1; nil }) do
        raise AppError.new("Youtube API returned status code 500")
      end
    end.to raise_error(AppError)

    expect(reconnects).to eq(0)
  end
end
