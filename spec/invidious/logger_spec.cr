require "../spec_helper"

Spectator.describe Invidious::LogHandler do
  it "writes log lines to the configured IO" do
    io = IO::Memory.new
    logger = Invidious::LogHandler.new(io, LogLevel::Info, use_color: false)

    logger.info("hello from spec")

    expect(io.to_s).to contain("[info] hello from spec")
    expect(io.to_s).to end_with("\n")
  end

  it "drops messages below the configured level" do
    io = IO::Memory.new
    logger = Invidious::LogHandler.new(io, LogLevel::Warn, use_color: false)

    logger.info("not shown")
    logger.error("shown")

    expect(io.to_s).not_to contain("not shown")
    expect(io.to_s).to contain("[error] shown")
  end
end
