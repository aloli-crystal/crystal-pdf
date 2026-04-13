require "../spec_helper"

describe "Stamps" do
  describe "Document#create_stamp" do
    it "creates a stamp and returns a reference" do
      doc = PDF::Document.new
      ref = doc.create_stamp("test_stamp") do |page|
        page.font "Helvetica", size: 12
        page.text "STAMP", at: {10, 20}
      end
      ref.should be_a(PDF::Objects::Reference)
    end

    it "raises for empty name" do
      doc = PDF::Document.new
      expect_raises(ArgumentError, /empty/) do
        doc.create_stamp("") { |_| }
      end
    end

    it "raises for duplicate name" do
      doc = PDF::Document.new
      doc.create_stamp("dup") { |_| }
      expect_raises(ArgumentError, /already exists/) do
        doc.create_stamp("dup") { |_| }
      end
    end

    it "creates a stamp with custom dimensions" do
      doc = PDF::Document.new
      ref = doc.create_stamp("small", 100, 50) do |page|
        page.fill_color(:red)
        page.rectangle(0, 0, 100, 50)
        page.fill
      end
      ref.should be_a(PDF::Objects::Reference)
    end
  end

  describe "Document#stamp" do
    it "retrieves a stamp by name" do
      doc = PDF::Document.new
      doc.create_stamp("logo") { |_| }
      ref = doc.stamp("logo")
      ref.should be_a(PDF::Objects::Reference)
    end

    it "raises for unknown stamp" do
      doc = PDF::Document.new
      expect_raises(ArgumentError, /Unknown stamp/) do
        doc.stamp("nonexistent")
      end
    end
  end

  describe "Page#stamp" do
    it "places a stamp on a page" do
      doc = PDF::Document.new
      stamp_ref = doc.create_stamp("watermark") do |page|
        page.font "Helvetica", size: 36
        page.fill_color(0.8, 0.8, 0.8)
        page.text "DRAFT", at: {10, 15}
      end

      doc.page do |page|
        page.font "Helvetica", size: 12
        page.text "Content", at: {72, 720}
        page.stamp(stamp_ref)
      end

      bytes = doc.to_slice
      TestHelpers.valid_pdf_header?(bytes).should be_true
      TestHelpers.valid_pdf_trailer?(bytes).should be_true
    end

    it "places a stamp at a specific position" do
      doc = PDF::Document.new
      stamp_ref = doc.create_stamp("marker", 50, 50) do |page|
        page.fill_color(:red)
        page.circle(25, 25, 20)
        page.fill
      end

      doc.page do |page|
        page.stamp_at(stamp_ref, {200, 300})
      end

      bytes = doc.to_slice
      TestHelpers.valid_pdf_header?(bytes).should be_true
    end
  end

  describe "stamp reuse" do
    it "allows stamping on multiple pages" do
      doc = PDF::Document.new
      stamp_ref = doc.create_stamp("header") do |page|
        page.font "Helvetica", size: 10
        page.text "Page Header", at: {72, 780}
      end

      3.times do
        doc.page do |page|
          page.stamp(stamp_ref)
          page.font "Helvetica", size: 12
          page.text "Body text", at: {72, 720}
        end
      end

      bytes = doc.to_slice
      TestHelpers.valid_pdf_header?(bytes).should be_true
      doc.pages.size.should eq(3)
    end
  end
end
