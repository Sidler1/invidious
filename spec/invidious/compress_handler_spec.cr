require "../spec_helper"

Spectator.describe FilteredCompressHandler do
  describe ".incompressible?" do
    it "recognises already-compressed asset types regardless of case" do
      %w(/favicon-32x32.png /fonts/ionicons.woff2 /img/banner.JPG /video/intro.webm).each do |path|
        expect(FilteredCompressHandler.incompressible?(path)).to be_true
      end
    end

    it "leaves text assets and pages compressible" do
      %w(/css/default.css /js/_helpers.js /watch /api/v1/videos/dQw4w9WgXcQ /).each do |path|
        expect(FilteredCompressHandler.incompressible?(path)).to be_false
      end
    end
  end
end
