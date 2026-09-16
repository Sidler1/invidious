require "../spec_helper"

# This spec file requires Config to be available. When running `crystal spec` (all specs together),
# helpers_spec.cr loads first and defines CONFIG, making the Config class available.
# The requires below ensure Config is loaded for this specific spec file.
require "../../src/invidious/jobs/base_job"
require "../../src/invidious/jobs"
require "../../src/invidious/user/preferences"
require "../../src/invidious/config"

Spectator.describe "Config.runtime_error" do
  def example_config
    Config.from_yaml(File.read("config/config.example.yml"))
  end

  it "accepts the example configuration" do
    expect(Config.runtime_error(example_config)).to be_nil
  end

  it "rejects an unknown proxy type" do
    config = example_config
    config.http_proxy = HTTPProxyConfig.from_yaml("host: localhost\nport: 8080\ntype: socks4")
    expect(Config.runtime_error(config)).to contain("http_proxy.type")
  end

  it "rejects a non-positive pool size" do
    config = example_config
    config.pool_size = 0
    expect(Config.runtime_error(config)).to contain("pool_size")
  end

  it "rejects a zero refresh interval" do
    config = example_config
    config.channel_refresh_interval = Time::Span.zero
    expect(Config.runtime_error(config)).to contain("channel_refresh_interval")
  end

  it "rejects a companion without an absolute http(s) private_url" do
    config = example_config
    config.invidious_companion = [Config::CompanionConfig.from_yaml("private_url: \"/companion\"")]
    expect(Config.runtime_error(config)).to contain("private_url")
  end
end
