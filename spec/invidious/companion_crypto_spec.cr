require "../spec_helper"

Spectator.describe "invidious companion check token" do
  TEST_KEY = "0123456789abcdef"

  # Generated with the Web Crypto API exactly as the companion's
  # encryptQuery.ts does it (see docs/superpowers/plans/2026-09-16-hardening.md, Task 27).
  WEB_CRYPTO_VECTOR = "AQIDBAUGBwgJCgsM0tBZ2BUmiszIAdZgv2TXCD838-7Gn-UkK-W6AaGyrKZe5Ncr6Kg="

  it "round-trips through encrypt and decrypt" do
    token = invidious_companion_encrypt("dQw4w9WgXcQ", TEST_KEY)
    plaintext = invidious_companion_decrypt(token, TEST_KEY)

    timestamp, video_id = plaintext.split("|", 2)
    expect(video_id).to eq("dQw4w9WgXcQ")
    expect(timestamp.to_i64).to be_close(Time.utc.to_unix, 5)
  end

  it "produces IV || ciphertext || tag in URL-safe base64" do
    token = invidious_companion_encrypt("dQw4w9WgXcQ", TEST_KEY)
    raw = Base64.decode(token)
    expect(raw.size).to eq(12 + "1700000000|dQw4w9WgXcQ".bytesize + 16)
    expect(token).not_to match(/[+\/]/)
  end

  it "decrypts a token produced by the companion's Web Crypto implementation" do
    expect(invidious_companion_decrypt(WEB_CRYPTO_VECTOR, TEST_KEY)).to eq("1700000000|dQw4w9WgXcQ")
  end

  it "rejects a tampered token" do
    tampered = WEB_CRYPTO_VECTOR.sub("0tBZ", "0tBa")
    expect { invidious_companion_decrypt(tampered, TEST_KEY) }.to raise_error(OpenSSL::Cipher::Error)
  end
end
