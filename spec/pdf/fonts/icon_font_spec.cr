require "../../spec_helper"

describe PDF::Fonts::IconFont do
  describe ".char" do
    it "returns the correct character for home icon" do
      result = PDF::Fonts::IconFont.char(:home)
      result.should eq("\uF015")
    end

    it "returns the correct character for search icon" do
      result = PDF::Fonts::IconFont.char(:search)
      result.should eq("\uF002")
    end

    it "returns a single character string" do
      result = PDF::Fonts::IconFont.char(:star)
      result.size.should eq(1)
    end

    it "raises for unknown icon name" do
      expect_raises(ArgumentError, /Unknown icon/) do
        PDF::Fonts::IconFont.char(:nonexistent_icon_xyz)
      end
    end
  end

  describe ".codepoint" do
    it "returns the codepoint for an icon" do
      PDF::Fonts::IconFont.codepoint(:home).should eq(0xF015)
    end

    it "raises for unknown icon" do
      expect_raises(ArgumentError, /Unknown icon/) do
        PDF::Fonts::IconFont.codepoint(:nonexistent_icon_xyz)
      end
    end
  end

  describe ".available_icons" do
    it "returns a non-empty array of symbols" do
      icons = PDF::Fonts::IconFont.available_icons
      icons.should_not be_empty
      icons.should be_a(Array(Symbol))
    end

    it "contains common icons" do
      icons = PDF::Fonts::IconFont.available_icons
      icons.should contain(:home)
      icons.should contain(:search)
      icons.should contain(:user)
      icons.should contain(:star)
    end
  end

  describe ".has_icon?" do
    it "returns true for known icons" do
      PDF::Fonts::IconFont.has_icon?(:home).should be_true
      PDF::Fonts::IconFont.has_icon?(:check).should be_true
    end

    it "returns false for unknown icons" do
      PDF::Fonts::IconFont.has_icon?(:nonexistent_icon_xyz).should be_false
    end
  end

  describe "alias mapping" do
    it "maps close to the same codepoint as times" do
      PDF::Fonts::IconFont.codepoint(:close).should eq(
        PDF::Fonts::IconFont.codepoint(:times)
      )
    end

    it "maps gear to the same codepoint as cog" do
      PDF::Fonts::IconFont.codepoint(:gear).should eq(
        PDF::Fonts::IconFont.codepoint(:cog)
      )
    end

    it "maps location to the same codepoint as map_marker" do
      PDF::Fonts::IconFont.codepoint(:location).should eq(
        PDF::Fonts::IconFont.codepoint(:map_marker)
      )
    end
  end
end
