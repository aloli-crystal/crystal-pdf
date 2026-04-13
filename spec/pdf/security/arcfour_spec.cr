require "../../spec_helper"

describe PDF::Security::Arcfour do
  it "encrypts and decrypts data symmetrically" do
    key = "secret".to_slice
    data = "Hello, World!".to_slice

    encrypted = PDF::Security::Arcfour.new(key).encrypt(data)
    encrypted.should_not eq(data)

    decrypted = PDF::Security::Arcfour.new(key).encrypt(encrypted)
    String.new(decrypted).should eq("Hello, World!")
  end

  it "produces different output for different keys" do
    data = "test data".to_slice

    enc1 = PDF::Security::Arcfour.new("key1".to_slice).encrypt(data)
    enc2 = PDF::Security::Arcfour.new("key2".to_slice).encrypt(data)

    enc1.should_not eq(enc2)
  end

  it "handles empty data" do
    key = "key".to_slice
    result = PDF::Security::Arcfour.new(key).encrypt(Bytes.empty)
    result.size.should eq(0)
  end

  it "produces output of the same length as input" do
    key = "testkey".to_slice
    data = Bytes.new(256) { |i| i.to_u8 }
    result = PDF::Security::Arcfour.new(key).encrypt(data)
    result.size.should eq(data.size)
  end

  it "encrypts strings" do
    key = "key".to_slice
    result = PDF::Security::Arcfour.new(key).encrypt("hello")
    result.should be_a(Bytes)
    result.size.should eq(5)
  end
end
