require "../spec_helper"

describe "Upstream version tracking" do
  it "defines UPSTREAM_VERSION" do
    PDF::UPSTREAM_VERSION.should eq("2.5.0")
  end

  it "defines VERSION" do
    PDF::VERSION.should be_a(String)
    PDF::VERSION.should_not be_empty
  end

  it "defines PDF_VERSION" do
    PDF::PDF_VERSION.should eq("1.7")
  end
end
