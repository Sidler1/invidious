require "../spec_helper"

Spectator.describe Invidious::CompanionProxy do
  describe ".caption_track_url" do
    # `caption.name` is free text that YouTube supplies. Left raw, a track
    # named with an "&" cuts the query short: the companion then compares
    # the truncated label against the real one and answers 404 for that
    # track. Invidious' own API already encodes this same value.
    it "percent-encodes a label that would otherwise break the query" do
      url = described_class.caption_track_url("", "dQw4w9WgXcQ", "R&B / Soul", nil)

      expect(url).to eq("/api/v1/captions/dQw4w9WgXcQ?label=R%26B+%2F+Soul")
      expect(url).not_to contain("&B")
    end

    it "appends the companion check token after the label" do
      url = described_class.caption_track_url("/companion", "dQw4w9WgXcQ", "English", "TOKEN")

      expect(url).to eq("/companion/api/v1/captions/dQw4w9WgXcQ?label=English&check=TOKEN")
    end

    it "prefixes an external companion public_url" do
      url = described_class.caption_track_url("http://c.example/companion", "dQw4w9WgXcQ", "English", "TOKEN")

      expect(url).to eq("http://c.example/companion/api/v1/captions/dQw4w9WgXcQ?label=English&check=TOKEN")
    end

    it "omits the check when no companion is configured" do
      url = described_class.caption_track_url("", "dQw4w9WgXcQ", "English", nil)

      expect(url).to eq("/api/v1/captions/dQw4w9WgXcQ?label=English")
    end
  end

  describe ".request_headers" do
    it "forwards only allow-listed headers" do
      incoming = HTTP::Headers{
        "Accept"        => "*/*",
        "Range"         => "bytes=0-1",
        "Cookie"        => "SID=secret",
        "Authorization" => "Bearer x",
        "Host"          => "invidious.example",
        "Content-Type"  => "application/json",
      }
      forwarded = described_class.request_headers(incoming)
      expect(forwarded["Accept"]).to eq("*/*")
      expect(forwarded["Range"]).to eq("bytes=0-1")
      expect(forwarded["Content-Type"]).to eq("application/json")
      expect(forwarded["Cookie"]?).to be_nil
      expect(forwarded["Authorization"]?).to be_nil
      expect(forwarded["Host"]?).to be_nil
    end
  end

  describe ".response_header_allowed?" do
    it "blocks hop-by-hop and security headers" do
      %w(Connection Transfer-Encoding Set-Cookie Content-Security-Policy Strict-Transport-Security Upgrade Trailer).each do |name|
        expect(described_class.response_header_allowed?(name)).to be_false
      end
    end

    it "allows content headers" do
      %w(Content-Type Content-Length Content-Range Cache-Control ETag).each do |name|
        expect(described_class.response_header_allowed?(name)).to be_true
      end
    end
  end

  describe ".upstream_path" do
    it "maps the public prefix onto the companion base path" do
      expect(described_class.upstream_path("/companion/latest_version", URI.parse("http://localhost:8282/companion"))).to eq("/companion/latest_version")
      expect(described_class.upstream_path("/companion/latest_version", URI.parse("http://localhost:8282/yt/"))).to eq("/yt/latest_version")
      expect(described_class.upstream_path("/companion/latest_version", URI.parse("http://localhost:8282"))).to eq("/latest_version")
    end
  end

  describe ".stream_redirect" do
    it "carries the original query and mints a fresh check token" do
      public_url = URI.parse("http://c.example/companion")
      query = URI::Params.parse("id=dQw4w9WgXcQ&itag=18")

      result = described_class.stream_redirect(public_url, "/latest_version", query, "dQw4w9WgXcQ")

      expect(result.starts_with?("http://c.example/companion/latest_version?")).to be_true
      expect(result).to contain("id=dQw4w9WgXcQ")
      expect(result).to contain("itag=18")
      expect(result.scan("check=").size).to eq(1)
    end

    it "drops a client-supplied check and replaces it with a fresh one" do
      public_url = URI.parse("http://c.example/companion")
      query = URI::Params.parse("check=stale&local=true")

      result = described_class.stream_redirect(public_url, "/latest_version", query, "dQw4w9WgXcQ")

      expect(result).to contain("local=true")
      expect(result).to_not contain("check=stale")
      expect(result.scan("check=").size).to eq(1)
    end
  end

  describe ".client_disconnect?" do
    it "is true when the client connection failed, even when wrapped" do
      client_error = HTTP::Server::ClientError.new("Error while writing data to the client", IO::Error.new("Broken pipe"))
      wrapped = Exception.new("companion response aborted mid-stream", cause: client_error)

      expect(described_class.client_disconnect?(client_error)).to be_true
      expect(described_class.client_disconnect?(wrapped)).to be_true
    end

    it "is false for companion-side failures" do
      upstream = Exception.new("aborted", cause: IO::Error.new("Connection reset by peer"))

      expect(described_class.client_disconnect?(upstream)).to be_false
      expect(described_class.client_disconnect?(Socket::ConnectError.new("refused"))).to be_false
    end
  end
end
