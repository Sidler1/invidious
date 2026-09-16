require "../spec_helper"
require "../../src/invidious/user/converters"

Spectator.describe "converters" do
  describe "convert_theme" do
    it "maps legacy boolean values" do
      expect(convert_theme("true")).to eq("dark")
      expect(convert_theme("false")).to eq("light")
    end

    it "passes known themes through" do
      expect(convert_theme("dark")).to eq("dark")
      expect(convert_theme("light")).to eq("light")
    end

    it "drops empty and unknown values" do
      expect(convert_theme(nil)).to be_nil
      expect(convert_theme("")).to be_nil
      expect(convert_theme("\"><form action=https://evil>")).to be_nil
    end
  end

  describe "sanitize_locale" do
    it "keeps locales that have a translation file" do
      expect(sanitize_locale("en-US")).to eq("en-US")
      expect(sanitize_locale("de")).to eq("de")
    end

    it "drops unknown locales" do
      expect(sanitize_locale(nil)).to be_nil
      expect(sanitize_locale("\"><meta http-equiv=refresh>")).to be_nil
    end
  end
end
