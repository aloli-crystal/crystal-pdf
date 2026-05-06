require "spec"
require "../../../src/pdf/encryption/rc4"

# Vecteurs de test RC4 issus de la RFC 6229 / wiki RC4.
# (Référence canonique — si ces tests passent, l'implémentation est
# conforme et interopérable.)
describe PDF::Encryption::RC4 do
  it "vecteur 'Key' / 'Plaintext' (Wikipedia)" do
    key = "Key".to_slice
    plain = "Plaintext".to_slice
    expected = Bytes[0xBB_u8, 0xF3_u8, 0x16_u8, 0xE8_u8, 0xD9_u8, 0x40_u8, 0xAF_u8, 0x0A_u8, 0xD3_u8]

    actual = PDF::Encryption::RC4.apply(key, plain)
    actual.should eq(expected)

    # Symétrie
    PDF::Encryption::RC4.apply(key, actual).should eq(plain)
  end

  it "vecteur 'Wiki' / 'pedia'" do
    key = "Wiki".to_slice
    plain = "pedia".to_slice
    expected = Bytes[0x10_u8, 0x21_u8, 0xBF_u8, 0x04_u8, 0x20_u8]

    PDF::Encryption::RC4.apply(key, plain).should eq(expected)
  end

  it "vecteur 'Secret' / 'Attack at dawn'" do
    key = "Secret".to_slice
    plain = "Attack at dawn".to_slice
    expected = Bytes[
      0x45_u8, 0xA0_u8, 0x1F_u8, 0x64_u8, 0x5F_u8, 0xC3_u8, 0x5B_u8,
      0x38_u8, 0x35_u8, 0x52_u8, 0x54_u8, 0x4B_u8, 0x9B_u8, 0xF5_u8,
    ]

    PDF::Encryption::RC4.apply(key, plain).should eq(expected)
  end

  it "lève sur clé vide" do
    expect_raises(ArgumentError, /must not be empty/) do
      PDF::Encryption::RC4.new(Bytes.empty)
    end
  end

  it "supporte des clés longues (128 bits)" do
    key = Bytes.new(16) { |i| i.to_u8 }
    plain = "Hello, encrypted PDF !".to_slice
    cipher = PDF::Encryption::RC4.apply(key, plain)
    decrypted = PDF::Encryption::RC4.apply(key, cipher)
    decrypted.should eq(plain)
  end

  it "deux applications avec la même instance produisent le même résultat (état non muté)" do
    key = "TestKey".to_slice
    plain = "Hello, World!".to_slice
    rc4 = PDF::Encryption::RC4.new(key)
    a = rc4.apply(plain)
    b = rc4.apply(plain)
    a.should eq(b)
  end
end
