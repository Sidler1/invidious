require "../spec_helper"

Spectator.describe "template_playlist" do
  it "skips entries that carry no videoId" do
    # Arrange: one regular video and one ProblematicTimelineItem ("parse-error")
    playlist = JSON.parse(%({
      "title": "Mix",
      "playlistId": "PL123",
      "videos": [
        {"videoId": "dQw4w9WgXcQ", "title": "Video", "author": "Author", "index": 0, "lengthSeconds": 212},
        {"type": "parse-error", "errorMessage": "boom", "errorBacktrace": "boom"}
      ]
    }))

    # Act
    html = template_playlist(playlist, false)

    # Assert
    expect(html.scan("<li ").size).to eq(1)
    expect(html).to contain("dQw4w9WgXcQ")
  end
end

Spectator.describe "template_mix" do
  it "skips entries that carry no videoId" do
    mix = JSON.parse(%({
      "title": "Mix",
      "mixId": "RD123",
      "videos": [
        {"videoId": "dQw4w9WgXcQ", "title": "Video", "author": "Author", "lengthSeconds": 212},
        {"type": "parse-error", "errorMessage": "boom", "errorBacktrace": "boom"}
      ]
    }))

    html = template_mix(mix, false)

    expect(html.scan("<li ").size).to eq(1)
    expect(html).to contain("dQw4w9WgXcQ")
  end
end
