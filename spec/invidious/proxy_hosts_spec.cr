require "../spec_helper"

Spectator.describe Invidious::ProxyHosts do
  describe ".valid_googlevideo_host?" do
    it "accepts real googlevideo and c.youtube hosts" do
      expect(described_class.valid_googlevideo_host?("rr3---sn-4g5e6nzl.googlevideo.com")).to be_true
      expect(described_class.valid_googlevideo_host?("r3---sn-abc.c.youtube.com")).to be_true
    end

    it "rejects userinfo, ports, paths and lookalike domains" do
      expect(described_class.valid_googlevideo_host?("x.googlevideo.com@10.0.0.5:8443")).to be_false
      expect(described_class.valid_googlevideo_host?("x.googlevideo.com:8443")).to be_false
      expect(described_class.valid_googlevideo_host?("attacker.example/x.googlevideo.com")).to be_false
      expect(described_class.valid_googlevideo_host?("x.googlevideo.com.evil.example")).to be_false
      expect(described_class.valid_googlevideo_host?("googlevideo.com")).to be_false
      expect(described_class.valid_googlevideo_host?("")).to be_false
    end
  end

  describe ".valid_googlevideo_redirect?" do
    it "accepts https redirects to allow-listed hosts" do
      expect(described_class.valid_googlevideo_redirect?(URI.parse("https://rr1---sn-x.googlevideo.com/videoplayback?a=1"))).to be_true
    end

    it "rejects plain http, other hosts, ports and userinfo" do
      expect(described_class.valid_googlevideo_redirect?(URI.parse("http://rr1---sn-x.googlevideo.com/v"))).to be_false
      expect(described_class.valid_googlevideo_redirect?(URI.parse("https://169.254.169.254/latest/meta-data/"))).to be_false
      expect(described_class.valid_googlevideo_redirect?(URI.parse("https://rr1---sn-x.googlevideo.com:8443/v"))).to be_false
      expect(described_class.valid_googlevideo_redirect?(URI.parse("https://u@rr1---sn-x.googlevideo.com/v"))).to be_false
      expect(described_class.valid_googlevideo_redirect?(URI.parse("/relative"))).to be_false
    end
  end

  describe ".valid_ytimg_subdomain?" do
    it "accepts the subdomains YouTube uses" do
      %w(i i1 i9 yt3 s).each do |sub|
        expect(described_class.valid_ytimg_subdomain?(sub)).to be_true
      end
    end

    it "rejects anything that could change the host" do
      ["", "evil.com/", "i/", "i?x", "i#x", "i@x", "toolongvalue", "9i", "I"].each do |sub|
        expect(described_class.valid_ytimg_subdomain?(sub)).to be_false
      end
    end
  end
end
