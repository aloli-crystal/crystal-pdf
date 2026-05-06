require "spec"
require "../../../src/pdf"

describe PDF::Encryption::AES do
  describe ".encrypt / .decrypt (avec IV préfixé, AES-128)" do
    it "round-trip : encrypt(plaintext) puis decrypt(ct) == plaintext" do
      key = Bytes[0x2b, 0x7e, 0x15, 0x16, 0x28, 0xae, 0xd2, 0xa6,
        0xab, 0xf7, 0x15, 0x88, 0x09, 0xcf, 0x4f, 0x3c]
      plaintext = "Le PDF est un format universel".to_slice

      ct = PDF::Encryption::AES.encrypt(key, plaintext)
      ct.size.should be > plaintext.size # IV (16) + padding inclus

      pt = PDF::Encryption::AES.decrypt(key, ct)
      String.new(pt).should eq("Le PDF est un format universel")
    end

    it "round-trip : empty plaintext (juste le padding PKCS#7)" do
      key = Bytes.new(16, 0x42_u8)
      ct = PDF::Encryption::AES.encrypt(key, Bytes.empty)
      ct.size.should eq(32) # IV (16) + 16 bytes de padding pur
      pt = PDF::Encryption::AES.decrypt(key, ct)
      pt.empty?.should be_true
    end

    it "round-trip : 16 octets exacts (force un bloc complet de padding)" do
      key = Bytes.new(16, 0x01_u8)
      pt = Bytes.new(16) { |i| i.to_u8 }
      ct = PDF::Encryption::AES.encrypt(key, pt)
      # IV (16) + 1 bloc data (16) + 1 bloc padding pur (16) = 48
      ct.size.should eq(48)
      out = PDF::Encryption::AES.decrypt(key, ct)
      out.should eq(pt)
    end
  end

  describe ".encrypt / .decrypt (avec IV préfixé, AES-256)" do
    it "round-trip avec une clé 256 bits" do
      key = Bytes.new(32) { |i| i.to_u8 }
      plaintext = ("A" * 100).to_slice
      ct = PDF::Encryption::AES.encrypt(key, plaintext)
      pt = PDF::Encryption::AES.decrypt(key, ct)
      pt.should eq(plaintext)
    end
  end

  describe ".encrypt_no_iv / .decrypt_no_iv (V=5 /OE /UE)" do
    it "round-trip sans IV préfixé, IV nul" do
      key = Bytes.new(32) { |i| i.to_u8 }
      iv = Bytes.new(16, 0_u8)
      pt = Bytes.new(32) { |i| (i * 7).to_u8 }

      ct = PDF::Encryption::AES.encrypt_no_iv(key, pt, iv, padding: false)
      ct.size.should eq(32) # pas de padding ajouté

      out = PDF::Encryption::AES.decrypt_no_iv(key, ct, iv, padding: false)
      out.should eq(pt)
    end
  end

  describe "validations" do
    it "lève ArgumentError sur une clé de taille incorrecte" do
      expect_raises(ArgumentError, /Taille de clé AES invalide/) do
        PDF::Encryption::AES.encrypt(Bytes.new(8), "data".to_slice)
      end
    end

    it "lève ArgumentError sur un blob trop court pour contenir l'IV" do
      key = Bytes.new(16)
      expect_raises(ArgumentError, /trop court/) do
        PDF::Encryption::AES.decrypt(key, Bytes.new(8))
      end
    end
  end
end
