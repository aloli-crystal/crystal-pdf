require "./spec_helper"
require "yaml"

describe PDF do
  it "VERSION matches shard.yml (compile-time read, pas de désynchro possible)" do
    yml = YAML.parse(File.read(File.join(__DIR__, "..", "shard.yml")))
    PDF::VERSION.should eq(yml["version"].as_s)
  end

  it "VERSION est au format SemVer X.Y.Z" do
    PDF::VERSION.should match(/^\d+\.\d+\.\d+$/)
  end

  it "has a PDF version" do
    PDF::PDF_VERSION.should eq("1.7")
  end
end

# Require all spec files
require "./pdf/objects/*"
require "./pdf/filters/*"
require "./pdf/fonts/*"
require "./pdf/fonts/truetype/*"
require "./pdf/document_spec"
require "./pdf/page_spec"
require "./integration/*"
