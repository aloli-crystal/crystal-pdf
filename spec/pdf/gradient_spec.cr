require "../spec_helper"

describe PDF::Gradient do
  describe ".linear" do
    it "creates a linear gradient pattern object" do
      doc = PDF::Document.new
      pattern = PDF::Gradient.linear(
        0, 0, 100, 100,
        {1.0, 0.0, 0.0}, {0.0, 0.0, 1.0},
        doc
      )
      pattern.should be_a(PDF::Objects::Indirect)
    end

    it "registers objects in the document" do
      doc = PDF::Document.new
      initial_count = doc.objects.size
      PDF::Gradient.linear(
        0, 0, 200, 200,
        {1.0, 1.0, 0.0}, {0.0, 1.0, 0.0},
        doc
      )
      # Should have created function, shading, and pattern objects
      (doc.objects.size - initial_count).should be >= 3
    end
  end

  describe ".radial" do
    it "creates a radial gradient with two circles" do
      doc = PDF::Document.new
      pattern = PDF::Gradient.radial(
        100, 100, 0,
        100, 100, 50,
        {1.0, 0.0, 0.0}, {0.0, 0.0, 1.0},
        doc
      )
      pattern.should be_a(PDF::Objects::Indirect)
    end

    it "creates a radial gradient with simple center+radius API" do
      doc = PDF::Document.new
      pattern = PDF::Gradient.radial(
        100, 100, 50,
        {1.0, 1.0, 0.0}, {0.0, 1.0, 0.0},
        doc
      )
      pattern.should be_a(PDF::Objects::Indirect)
    end
  end

  describe "page integration" do
    it "renders a page with a linear gradient fill" do
      doc = PDF::Document.new
      doc.page do |page|
        page.rectangle(100, 100, 200, 200)
        page.fill_gradient_linear(100, 100, 300, 300,
          {1.0, 0.0, 0.0}, {0.0, 0.0, 1.0})
      end

      bytes = doc.to_slice
      TestHelpers.valid_pdf_header?(bytes).should be_true
      TestHelpers.valid_pdf_trailer?(bytes).should be_true
    end

    it "renders a page with a radial gradient fill" do
      doc = PDF::Document.new
      doc.page do |page|
        page.circle(200, 200, 80)
        page.fill_gradient_radial(200, 200, 0, 200, 200, 80,
          {1.0, 1.0, 0.0}, {1.0, 0.0, 0.0})
      end

      bytes = doc.to_slice
      TestHelpers.valid_pdf_header?(bytes).should be_true
    end

    it "renders a page with a stroke gradient" do
      doc = PDF::Document.new
      doc.page do |page|
        page.line_width(5)
        page.rectangle(50, 50, 200, 200)
        page.stroke_gradient_linear(50, 50, 250, 250,
          {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0})
      end

      bytes = doc.to_slice
      TestHelpers.valid_pdf_header?(bytes).should be_true
    end
  end
end
