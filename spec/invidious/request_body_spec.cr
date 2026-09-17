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

Spectator.describe "form_body_valid?" do
  it "is false for a malformed multipart body" do
    headers = HTTP::Headers{"Content-Type" => "multipart/form-data; boundary=----x"}
    request = HTTP::Request.new("POST", "/login", headers, "not a multipart body")

    expect(form_body_valid?(Kemal::ParamParser.new(request))).to be_false
  end

  it "is false for a multipart content type without boundary" do
    headers = HTTP::Headers{"Content-Type" => "multipart/form-data"}
    request = HTTP::Request.new("POST", "/login", headers, "x")

    expect(form_body_valid?(Kemal::ParamParser.new(request))).to be_false
  end

  it "is true for a well-formed urlencoded body" do
    headers = HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}
    request = HTTP::Request.new("POST", "/login", headers, "email=a%40b.c&password=x")
    params = Kemal::ParamParser.new(request)

    expect(form_body_valid?(params)).to be_true
    expect(params.body["email"]).to eq("a@b.c")
  end
end
