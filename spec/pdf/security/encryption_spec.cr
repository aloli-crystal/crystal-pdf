require "../../spec_helper"

describe PDF::Security::Encryption do
  describe "#initialize" do
    it "creates an encryption with default settings" do
      enc = PDF::Security::Encryption.new
      enc.user_password.should eq("")
      enc.revision.should eq(2)
      enc.version.should eq(1)
    end

    it "creates an encryption with 128-bit key" do
      enc = PDF::Security::Encryption.new(key_length: 128)
      enc.revision.should eq(3)
      enc.version.should eq(2)
    end

    it "raises for invalid key length" do
      expect_raises(ArgumentError, /Key length/) do
        PDF::Security::Encryption.new(key_length: 64)
      end
    end

    it "creates an encryption with passwords" do
      enc = PDF::Security::Encryption.new(
        user_password: "user",
        owner_password: "owner"
      )
      enc.user_password.should eq("user")
      enc.owner_password.should eq("owner")
    end

    it "falls back owner to user password when empty" do
      enc = PDF::Security::Encryption.new(user_password: "pass")
      enc.owner_password.should eq("pass")
    end
  end

  describe "#to_dictionary" do
    it "produces a valid encryption dictionary" do
      enc = PDF::Security::Encryption.new
      dict = enc.to_dictionary
      dict.should be_a(PDF::Objects::Dictionary)

      pdf = dict.to_pdf
      pdf.should contain("/Filter /Standard")
      pdf.should contain("/V 1")
      pdf.should contain("/R 2")
      pdf.should contain("/O ")
      pdf.should contain("/U ")
      pdf.should contain("/P ")
    end
  end

  describe "#encrypt_string" do
    it "encrypts a string" do
      enc = PDF::Security::Encryption.new(user_password: "test")
      result = enc.encrypt_string("Hello", 1, 0)
      result.should be_a(Bytes)
      result.size.should eq(5)
    end

    it "produces different results for different objects" do
      enc = PDF::Security::Encryption.new(user_password: "test")
      r1 = enc.encrypt_string("Hello", 1, 0)
      r2 = enc.encrypt_string("Hello", 2, 0)
      r1.should_not eq(r2)
    end
  end

  describe "permissions" do
    it "sets print permission" do
      enc = PDF::Security::Encryption.new(
        permissions: [PDF::Security::Permission::Print]
      )
      # Bit 3 (value 4) should be set
      (enc.permissions_value & 4).should eq(4)
    end

    it "sets multiple permissions" do
      enc = PDF::Security::Encryption.new(
        permissions: [
          PDF::Security::Permission::Print,
          PDF::Security::Permission::Copy,
        ]
      )
      (enc.permissions_value & 4).should eq(4)   # Print
      (enc.permissions_value & 16).should eq(16)  # Copy
    end

    it "denies modify when not in permissions list" do
      enc = PDF::Security::Encryption.new(
        permissions: [PDF::Security::Permission::Print]
      )
      # Bit 4 (value 8) should NOT be set
      (enc.permissions_value & 8).should eq(0)
    end
  end

  describe "document integration" do
    it "creates an encrypted PDF" do
      doc = PDF::Document.new
      doc.encrypt(user_password: "", owner_password: "owner")

      doc.page do |page|
        page.font "Helvetica", size: 12
        page.text "Encrypted content", at: {72, 720}
      end

      bytes = doc.to_slice
      TestHelpers.valid_pdf_header?(bytes).should be_true
      TestHelpers.valid_pdf_trailer?(bytes).should be_true

      # The trailer should contain an /Encrypt entry
      content = String.new(bytes)
      content.should contain("/Encrypt")
    end
  end
end
