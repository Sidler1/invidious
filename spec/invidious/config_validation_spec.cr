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

  it "rejects a non-positive database pool size" do
    config = example_config
    config.database_pool_size = 0
    expect(Config.runtime_error(config)).to contain("database_pool_size")
  end

  it "accepts a 16-character alphanumeric companion key" do
    config = example_config
    config.invidious_companion = [Config::CompanionConfig.from_yaml("private_url: \"http://localhost:8282/companion\"")]
    config.invidious_companion_key = "aA0bB1cC2dD3eE4f"
    expect(Config.runtime_error(config)).to be_nil
  end

  it "rejects a companion key that is not 16 characters" do
    config = example_config
    config.invidious_companion = [Config::CompanionConfig.from_yaml("private_url: \"http://localhost:8282/companion\"")]
    config.invidious_companion_key = "tooshort"
    expect(Config.runtime_error(config)).to contain("invidious_companion_key")
  end

  it "rejects a 16-character companion key containing non-alphanumeric characters" do
    config = example_config
    config.invidious_companion = [Config::CompanionConfig.from_yaml("private_url: \"http://localhost:8282/companion\"")]
    config.invidious_companion_key = "abcd1234!$%&5678"
    expect(Config.runtime_error(config)).to contain("invidious_companion_key")
  end

  it "does not check the companion key when no companion is configured" do
    config = example_config
    config.invidious_companion_key = "not a valid key"
    expect(Config.runtime_error(config)).to be_nil
  end
end

Spectator.describe "Config.runtime_warnings" do
  def example_config
    Config.from_yaml(File.read("config/config.example.yml"))
  end

  def companion_config(private_url : String)
    Config::CompanionConfig.from_yaml("private_url: #{private_url.inspect}")
  end

  it "returns no warnings for the example configuration" do
    expect(Config.runtime_warnings(example_config)).to be_empty
  end

  it "warns when a companion private_url has no base path" do
    config = example_config
    config.invidious_companion = [companion_config("http://localhost:8282")]
    warnings = Config.runtime_warnings(config)
    expect(warnings.size).to eq(1)
    expect(warnings[0]).to contain("private_url")
    expect(warnings[0]).to contain("base_path")
  end

  it "warns when a companion private_url has a bare root path" do
    config = example_config
    config.invidious_companion = [companion_config("http://localhost:8282/")]
    expect(Config.runtime_warnings(config).size).to eq(1)
  end

  it "does not warn when a companion private_url includes a base path" do
    config = example_config
    config.invidious_companion = [companion_config("http://localhost:8282/companion")]
    expect(Config.runtime_warnings(config)).to be_empty
  end
end
