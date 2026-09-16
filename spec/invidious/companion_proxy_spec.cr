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
end
