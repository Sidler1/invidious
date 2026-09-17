require "../../parsers_helper.cr"

Spectator.describe "Video#storyboards" do
  it "returns no storyboards when the player response has none" do
    # Arrange: a player response without a "storyboards" key (e.g. jNQXAC9IVRw)
    video = Video.new({
      id:      "jNQXAC9IVRw",
      info:    {"lengthSeconds" => JSON::Any.new(19_i64)},
      updated: Time.utc,
    })

    # Act
    storyboards = video.storyboards

    # Assert
    expect(storyboards).to be_empty
  end
end
