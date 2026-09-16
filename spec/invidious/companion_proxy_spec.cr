require "../spec_helper"

Spectator.describe Invidious::CompanionProxy do
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
      %w(Connection Transfer-Encoding Set-Cookie Content-Security-Policy Strict-Transport-Security).each do |name|
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
end
