require "../spec_helper"

describe PDF::Parser do
  describe "#parse_value" do
    it "analyse un nombre entier" do
      p = parser_for("42")
      result = p.parse_value
      result.should be_a(PDF::Objects::Number)
      result.as(PDF::Objects::Number).to_i64.should eq(42)
    end

    it "analyse un nombre négatif" do
      p = parser_for("-17")
      result = p.parse_value
      result.should be_a(PDF::Objects::Number)
      result.as(PDF::Objects::Number).to_i64.should eq(-17)
    end

    it "analyse un nombre réel" do
      p = parser_for("3.14")
      result = p.parse_value
      result.should be_a(PDF::Objects::Number)
      result.as(PDF::Objects::Number).to_f64.should be_close(3.14, 0.001)
    end

    it "analyse true" do
      p = parser_for("true")
      result = p.parse_value
      result.should be_a(PDF::Objects::Boolean)
      result.as(PDF::Objects::Boolean).value.should be_true
    end

    it "analyse false" do
      p = parser_for("false")
      result = p.parse_value
      result.should be_a(PDF::Objects::Boolean)
      result.as(PDF::Objects::Boolean).value.should be_false
    end

    it "analyse null" do
      p = parser_for("null")
      result = p.parse_value
      result.should be_a(PDF::Objects::Null)
    end

    it "analyse un nom" do
      p = parser_for("/Type")
      result = p.parse_value
      result.should be_a(PDF::Objects::Name)
      result.as(PDF::Objects::Name).value.should eq("Type")
    end

    it "analyse un nom avec échappement hexadécimal" do
      p = parser_for("/Name#20With#20Spaces")
      result = p.parse_value
      result.should be_a(PDF::Objects::Name)
      result.as(PDF::Objects::Name).value.should eq("Name With Spaces")
    end

    it "analyse une chaîne littérale" do
      p = parser_for("(Hello, World!)")
      result = p.parse_value
      result.should be_a(PDF::Objects::Str)
      result.as(PDF::Objects::Str).value.should eq("Hello, World!")
    end

    it "analyse une chaîne avec parenthèses imbriquées" do
      p = parser_for("(Hello (nested) World)")
      result = p.parse_value
      result.should be_a(PDF::Objects::Str)
      result.as(PDF::Objects::Str).value.should eq("Hello (nested) World")
    end

    it "analyse une chaîne avec séquences d'échappement" do
      p = parser_for("(Line1\\nLine2)")
      result = p.parse_value
      result.should be_a(PDF::Objects::Str)
      result.as(PDF::Objects::Str).value.should eq("Line1\nLine2")
    end

    it "analyse une chaîne hexadécimale" do
      p = parser_for("<48656C6C6F>")
      result = p.parse_value
      result.should be_a(PDF::Objects::Str)
      result.as(PDF::Objects::Str).value.should eq("Hello")
    end

    it "analyse un tableau" do
      p = parser_for("[1 2 3]")
      result = p.parse_value
      result.should be_a(PDF::Objects::Array)
      arr = result.as(PDF::Objects::Array)
      arr.size.should eq(3)
      arr[0].as(PDF::Objects::Number).to_i64.should eq(1)
      arr[2].as(PDF::Objects::Number).to_i64.should eq(3)
    end

    it "analyse un tableau avec des types mélangés" do
      p = parser_for("[/Name (text) 42 true]")
      result = p.parse_value
      arr = result.as(PDF::Objects::Array)
      arr.size.should eq(4)
      arr[0].should be_a(PDF::Objects::Name)
      arr[1].should be_a(PDF::Objects::Str)
      arr[2].should be_a(PDF::Objects::Number)
      arr[3].should be_a(PDF::Objects::Boolean)
    end

    it "analyse une référence indirecte" do
      p = parser_for("5 0 R")
      result = p.parse_value
      result.should be_a(PDF::Objects::Reference)
      ref = result.as(PDF::Objects::Reference)
      ref.object_number.should eq(5)
      ref.generation.should eq(0)
    end

    it "analyse un dictionnaire" do
      p = parser_for("<</Type /Page /Count 5>>")
      result = p.parse_value
      result.should be_a(PDF::Objects::Dictionary)
      dict = result.as(PDF::Objects::Dictionary)
      dict["Type"].as(PDF::Objects::Name).value.should eq("Page")
      dict["Count"].as(PDF::Objects::Number).to_i64.should eq(5)
    end

    it "analyse un dictionnaire imbriqué" do
      p = parser_for("<</Resources <</Font <</F1 2 0 R>>>>>>")
      result = p.parse_value
      dict = result.as(PDF::Objects::Dictionary)
      resources = dict["Resources"].as(PDF::Objects::Dictionary)
      font = resources["Font"].as(PDF::Objects::Dictionary)
      f1 = font["F1"].as(PDF::Objects::Reference)
      f1.object_number.should eq(2)
    end
  end

  describe "#parse_object_at" do
    it "analyse un objet indirect" do
      text = "5 0 obj\n<</Type /Page>>\nendobj"
      p = parser_for(text)
      obj = p.parse_object_at(0)
      obj.object_number.should eq(5)
      obj.generation.should eq(0)
      obj.value.should be_a(PDF::Objects::Dictionary)
    end
  end

  describe "#skip_whitespace" do
    it "saute les espaces, tabulations et retours à la ligne" do
      p = parser_for("  \t\n\r  42")
      p.skip_whitespace
      result = p.parse_value
      result.as(PDF::Objects::Number).to_i64.should eq(42)
    end

    it "saute les commentaires" do
      p = parser_for("% ceci est un commentaire\n42")
      p.skip_whitespace
      result = p.parse_value
      result.as(PDF::Objects::Number).to_i64.should eq(42)
    end
  end

  describe "analyse d'un PDF complet" do
    it "analyse l'en-tête, xref et trailer d'un PDF généré" do
      path = File.join(__DIR__, "..", "fixtures", "single_page.pdf")
      data = File.read(path).to_slice
      parser = PDF::Parser.new(data)
      parser.parse!

      parser.version.should eq("1.7")
      parser.xref.size.should be > 0
      parser.trailer.has_key?("Root").should be_true
      parser.trailer.has_key?("Size").should be_true
    end
  end
end

# Helpers au niveau module pour les macros describe
def parser_for(text : String) : PDF::Parser
  PDF::Parser.new(text.to_slice)
end
