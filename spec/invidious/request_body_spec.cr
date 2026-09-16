require "../spec_helper"

Spectator.describe "read_body_limited" do
  it "returns the body when it fits" do
    expect(read_body_limited(IO::Memory.new("hello"), 5)).to eq("hello")
  end

  it "returns nil when the body exceeds the limit" do
    expect(read_body_limited(IO::Memory.new("hello!"), 5)).to be_nil
  end

  it "returns an empty string for a missing body" do
    expect(read_body_limited(nil, 5)).to eq("")
  end

  it "does not read more than limit + 1 bytes" do
    io = IO::Memory.new("x" * 100)
    read_body_limited(io, 10)
    expect(io.pos).to eq(11)
  end
end
