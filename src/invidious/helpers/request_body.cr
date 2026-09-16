# Upper bounds for request bodies that are read fully into memory. Kemal has
# no global body limit, so endpoints that buffer must enforce one themselves.
WEBHOOK_MAX_BODY_BYTES =  1_048_576 # 1 MiB; PubSubHubbub Atom payloads are a few KiB
IMPORT_MAX_BODY_BYTES  = 16_777_216 # 16 MiB; subscription/history exports

# Reads at most `limit` bytes of `io`. Returns `nil` when the body is larger
# than `limit` so the caller can answer 413 instead of buffering it all.
def read_body_limited(io : IO?, limit : Int) : String?
  return "" if io.nil?

  body = IO::Sized.new(io, read_size: limit + 1).gets_to_end
  return nil if body.bytesize > limit
  body
end
