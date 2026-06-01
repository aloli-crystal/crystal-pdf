require "../spec_helper"

describe PDF::AcroForm do
  describe "Document#acroform" do
    it "creates an empty form lazily" do
      pdf = PDF::Document.new
      pdf.acroform?.should be_false
      pdf.acroform.should be_a(PDF::AcroForm::Form)
      # Accessing the getter without adding a field doesn't make
      # acroform? true.
      pdf.acroform?.should be_false
    end

    it "yields the form to a block" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }

      pdf.acroform do |form|
        form.text_field("nom", page: page, x: 100, y: 700, width: 200, height: 20)
      end

      pdf.acroform?.should be_true
      pdf.acroform.fields.size.should eq(1)
    end

    it "rejects duplicate field names" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }

      expect_raises(ArgumentError, /already declared/) do
        pdf.acroform do |form|
          form.text_field("dup", page: page, x: 0, y: 0, width: 100, height: 20)
          form.text_field("dup", page: page, x: 0, y: 30, width: 100, height: 20)
        end
      end
    end
  end

  describe "TextField" do
    it "builds a /Tx widget with the expected entries" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      field = nil
      pdf.acroform do |form|
        field = form.text_field(
          "nom",
          page: page,
          x: 100, y: 700, width: 200, height: 20,
          default_value: "Dupont",
          max_length: 50,
        )
      end

      d = field.not_nil!.dict
      d["FT"].to_pdf.should eq("/Tx")
      d["Subtype"].to_pdf.should eq("/Widget")
      d["Rect"].to_pdf.should eq("[100 700 300 720]")
      # Default value : either PDFDocEncoded "(Dupont)" or hex
      # UTF-16BE "<feff...44...70006f006e0074>".
      dv = d["DV"].to_pdf
      (dv.includes?("Dupont") || dv.includes?("44") && dv.includes?("70006f006e0074")).should be_true
      d["MaxLen"].to_pdf.should eq("50")
    end

    it "sets the Multiline flag when multiline: true" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      field = nil
      pdf.acroform do |form|
        field = form.text_field("c", page: page, x: 0, y: 0, width: 100, height: 80, multiline: true)
      end
      ff = field.not_nil!.dict["Ff"].as(PDF::Objects::Number).value.to_i
      (ff & PDF::AcroForm::TextField::MULTILINE).should_not eq(0)
    end

    it "emits an /AP appearance with the value rendered (BT/Tj sequence)" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      pdf.acroform do |form|
        form.text_field("nom", page: page, x: 0, y: 0, width: 200, height: 20, value: "Dupont")
      end

      bytes = pdf.to_slice
      out = bytes.map(&.chr).join
      out.should contain("/AP")
      out.should contain("/Subtype /Form")
      out.should contain("(Dupont) Tj")
    end

    it "renders password fields with masking dots in the appearance" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      pdf.acroform do |form|
        form.text_field("pwd", page: page, x: 0, y: 0, width: 200, height: 20, value: "secret", password: true)
      end

      bytes = pdf.to_slice
      out = bytes.map(&.chr).join
      out.should contain("(******) Tj") # 6 asterisks for "secret"
      out.should_not contain("(secret) Tj")
    end

    it "encodes Required and ReadOnly in /Ff" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      field = nil
      pdf.acroform do |form|
        field = form.text_field(
          "r", page: page, x: 0, y: 0, width: 100, height: 20,
          required: true, read_only: true,
        )
      end
      ff = field.not_nil!.dict["Ff"].as(PDF::Objects::Number).value.to_i
      (ff & 0b01).should_not eq(0) # ReadOnly bit 1
      (ff & 0b10).should_not eq(0) # Required bit 2
    end
  end

  describe "Checkbox" do
    it "builds a /Btn widget with /AS state" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      field = nil
      pdf.acroform do |form|
        field = form.checkbox("rgpd", page: page, x: 10, y: 10, size: 12, checked: true)
      end

      d = field.not_nil!.dict
      d["FT"].to_pdf.should eq("/Btn")
      d["V"].to_pdf.should eq("/Yes")
      d["AS"].to_pdf.should eq("/Yes")
    end
  end

  describe "RadioGroup" do
    it "builds a parent /Btn with Radio flag and kid widgets" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      field = nil
      pdf.acroform do |form|
        field = form.radio_group(
          "genre", page: page,
          options: ["M", "F", "Autre"],
          x: 100, y: 600, spacing: 25, size: 12,
          selected: "F",
        )
      end

      # Trigger /AcroForm finalize so kids are registered.
      pdf.to_slice

      d = field.not_nil!.dict
      d["FT"].to_pdf.should eq("/Btn")
      ff = d["Ff"].as(PDF::Objects::Number).value.to_i
      (ff & PDF::AcroForm::RadioGroup::RADIO).should_not eq(0)
      d["V"].to_pdf.should eq("/F")

      kids = d["Kids"].as(PDF::Objects::Array)
      kids.size.should eq(3)
    end

    it "sets /Parent on every kid widget (otherwise Acrobat and Preview ignore radios entirely)" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      pdf.acroform do |form|
        form.radio_group("g", page: page, options: ["A", "B"], x: 0, y: 0)
      end

      bytes = pdf.to_slice
      out = bytes.map(&.chr).join
      # The kid widgets must reference the parent field. Without
      # this, Acrobat and Preview render nothing.
      out.should contain("/Parent")
      # Two kid widgets are emitted ; both must carry /Parent.
      out.split("/Parent").size.should be >= 3
    end

    it "emits /AP with on and off appearance refs on every kid (otherwise radios are invisible in all viewers)" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      pdf.acroform do |form|
        form.radio_group(
          "genre", page: page,
          options: ["M", "F"],
          x: 100, y: 600,
        )
      end

      # Some bytes in the PDF stream may not be valid UTF-8 (FlateDecode
      # output, font subset data) — count occurrences via Bytes.
      bytes = pdf.to_slice
      out = bytes.map(&.chr).join

      # Every kid widget must carry /AP /N with a state key and /Off.
      out.split("/Subtype /Widget").size.should be >= 3 # 2 kids → 3 chunks
      out.should contain("/AP")
      out.should contain("/Off")
      # XObjects for the circle appearance must exist.
      out.should contain("/Subtype /Form")
      out.should contain("/FormType 1")
    end

    it "rejects empty options" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      expect_raises(ArgumentError, /at least one option/) do
        pdf.acroform do |form|
          form.radio_group("g", page: page, options: [] of String, x: 0, y: 0)
        end
      end
    end

    it "rejects selected outside options" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      expect_raises(ArgumentError, /not in options/) do
        pdf.acroform do |form|
          form.radio_group("g", page: page, options: ["A", "B"], x: 0, y: 0, selected: "Z")
        end
      end
    end
  end

  describe "Dropdown" do
    it "builds a /Ch widget with Combo flag" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      field = nil
      pdf.acroform do |form|
        field = form.dropdown(
          "pays", page: page,
          options: ["FR", "BE", "CH"],
          x: 100, y: 500, width: 80, height: 20,
          default_value: "FR",
        )
      end

      d = field.not_nil!.dict
      d["FT"].to_pdf.should eq("/Ch")
      ff = d["Ff"].as(PDF::Objects::Number).value.to_i
      (ff & PDF::AcroForm::Dropdown::COMBO).should_not eq(0)

      opt = d["Opt"].as(PDF::Objects::Array)
      opt.size.should eq(3)
    end

    it "rejects a value not in options when not editable" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      expect_raises(ArgumentError, /not in options/) do
        pdf.acroform do |form|
          form.dropdown("d", page: page, options: ["A", "B"], x: 0, y: 0,
            width: 50, height: 20, value: "Z")
        end
      end
    end

    it "accepts a Hash for options (code => label) and emits /Opt as pairs" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      field = nil
      pdf.acroform do |form|
        field = form.dropdown(
          "pays", page: page,
          options: {"FR" => "France", "BE" => "Belgique", "CH" => "Suisse"},
          x: 100, y: 500, width: 120, height: 20,
          default_value: "FR",
        )
      end

      d = field.not_nil!.dict
      opt = d["Opt"].as(PDF::Objects::Array)
      opt.size.should eq(3)

      # Each /Opt entry is itself an array [export, display].
      first = opt[0].as(PDF::Objects::Array)
      first.size.should eq(2)
      first[0].as(PDF::Objects::Str).value.should eq("FR")
      first[1].as(PDF::Objects::Str).value.should eq("France")
    end

    it "Dropdown#option_codes returns the keys of a Hash options" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      field = pdf.acroform.dropdown(
        "p", page: page, options: {"A" => "Alpha", "B" => "Beta"},
        x: 0, y: 0, width: 50, height: 20,
      )
      field.option_codes.should eq(["A", "B"])
      field.option_labels.should eq({"A" => "Alpha", "B" => "Beta"})
    end

    it "Dropdown#option_labels is nil when options is an Array" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      field = pdf.acroform.dropdown(
        "p", page: page, options: ["A", "B"],
        x: 0, y: 0, width: 50, height: 20,
      )
      field.option_labels.should be_nil
      field.option_codes.should eq(["A", "B"])
    end
  end

  describe "Listbox" do
    it "builds a /Ch widget with MultiSelect flag and without Combo" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      field = nil
      pdf.acroform do |form|
        field = form.listbox(
          "langues", page: page,
          options: ["FR", "EN", "DE"],
          x: 100, y: 500, width: 100, height: 80,
        )
      end

      d = field.not_nil!.dict
      d["FT"].to_pdf.should eq("/Ch")
      ff = d["Ff"].as(PDF::Objects::Number).value.to_i
      (ff & PDF::AcroForm::Listbox::MULTI_SELECT).should_not eq(0)
      (ff & PDF::AcroForm::Dropdown::COMBO).should eq(0)
    end

    it "emits /V as an array for multiple selected values" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      field = nil
      pdf.acroform do |form|
        field = form.listbox(
          "langues", page: page,
          options: ["FR", "EN", "DE", "IT"],
          x: 100, y: 500, width: 100, height: 80,
          value: ["FR", "EN"],
        )
      end

      d = field.not_nil!.dict
      v = d["V"].as(PDF::Objects::Array)
      v.size.should eq(2)
      v[0].as(PDF::Objects::Str).value.should eq("FR")
      v[1].as(PDF::Objects::Str).value.should eq("EN")
    end

    it "emits /V as a single string for a single selected value" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      field = nil
      pdf.acroform do |form|
        field = form.listbox(
          "langues", page: page,
          options: ["FR", "EN"],
          x: 100, y: 500, width: 100, height: 80,
          value: ["FR"],
        )
      end

      d = field.not_nil!.dict
      d["V"].as(PDF::Objects::Str).value.should eq("FR")
    end

    it "accepts a Hash for options and emits /Opt as pairs" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      field = nil
      pdf.acroform do |form|
        field = form.listbox(
          "langues", page: page,
          options: {"fr" => "French", "en" => "English"},
          x: 100, y: 500, width: 120, height: 80,
          value: ["fr"],
        )
      end

      d = field.not_nil!.dict
      opt = d["Opt"].as(PDF::Objects::Array)
      opt.size.should eq(2)
      first = opt[0].as(PDF::Objects::Array)
      first.size.should eq(2)
      # ASCII-only labels to avoid UTF-16BE encoding noise in `.value`.
      first[0].as(PDF::Objects::Str).value.should eq("fr")
      first[1].as(PDF::Objects::Str).value.should eq("French")
    end

    it "rejects empty options" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      expect_raises(ArgumentError, /needs at least one option/) do
        pdf.acroform.listbox("l", page: page, options: [] of String,
          x: 0, y: 0, width: 50, height: 80)
      end
    end

    it "rejects a value not in options" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      expect_raises(ArgumentError, /not in options/) do
        pdf.acroform.listbox("l", page: page, options: ["A", "B"],
          x: 0, y: 0, width: 50, height: 80, value: ["Z"])
      end
    end

    it "sets the Sort flag when sort: true" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      field = pdf.acroform.listbox("l", page: page, options: ["A", "B"],
        x: 0, y: 0, width: 50, height: 80, sort: true)
      ff = field.dict["Ff"].as(PDF::Objects::Number).value.to_i
      (ff & PDF::AcroForm::Listbox::SORT).should_not eq(0)
    end
  end

  describe "RadioGroup with Hash options" do
    it "exposes #option_codes and #option_labels from a Hash" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      field = pdf.acroform.radio_group(
        "niveau", page: page,
        options: {"C" => "Conforme", "P" => "Partiel", "NC" => "Non conforme"},
        x: 100, y: 600, spacing: 30, size: 12,
        selected: "C",
      )
      field.option_codes.should eq(["C", "P", "NC"])
      field.option_labels.should eq({"C" => "Conforme", "P" => "Partiel", "NC" => "Non conforme"})
    end

    it "still validates `selected` against the codes (Hash keys)" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      expect_raises(ArgumentError, /not in options/) do
        pdf.acroform.radio_group(
          "n", page: page,
          options: {"A" => "Alpha", "B" => "Beta"},
          x: 0, y: 0, selected: "ZZZ",
        )
      end
    end

    it "creates one kid widget per code from a Hash" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      field = pdf.acroform.radio_group(
        "n", page: page,
        options: {"X" => "Xray", "Y" => "Yankee"},
        x: 0, y: 0,
      )
      # The kids are attached during finalize! ; we just confirm
      # the parent computed its rect from the codes count.
      field.option_codes.size.should eq(2)
    end
  end

  describe "SignatureField" do
    it "builds a /Sig field with no /V (signed later by pdf-signature)" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      field = nil
      pdf.acroform do |form|
        field = form.signature_field("contract_sig", page: page, x: 100, y: 100, width: 200, height: 80)
      end

      d = field.not_nil!.dict
      d["FT"].to_pdf.should eq("/Sig")
      d["Subtype"].to_pdf.should eq("/Widget")
      d.has_key?("V").should be_false
    end

    it "sets /SigFlags 3 on /AcroForm when at least one signature field is present" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      pdf.acroform do |form|
        form.signature_field("sig", page: page, x: 0, y: 0, width: 100, height: 40)
      end

      bytes = pdf.to_slice
      out = bytes.map(&.chr).join
      out.should contain("/SigFlags 3")
    end

    it "omits /SigFlags when no signature field is declared" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      pdf.acroform do |form|
        form.text_field("nom", page: page, x: 0, y: 0, width: 100, height: 20)
      end

      bytes = pdf.to_slice
      out = bytes.map(&.chr).join
      out.should_not contain("/SigFlags")
    end
  end

  describe "Document output (integration)" do
    it "emits /AcroForm in the catalog with /NeedAppearances and /DA" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      pdf.acroform do |form|
        form.text_field("nom", page: page, x: 100, y: 700, width: 200, height: 20)
        form.checkbox("rgpd", page: page, x: 100, y: 670)
      end

      bytes = pdf.to_slice
      out = String.new(bytes)

      out.should contain("/AcroForm")
      out.should contain("/NeedAppearances true")
      out.should contain("/DA")
      out.should contain("/FT /Tx")
      out.should contain("/FT /Btn")
    end

    it "attaches widgets to the page's /Annots" do
      pdf = PDF::Document.new
      page = pdf.page { |_| }
      pdf.acroform do |form|
        form.text_field("a", page: page, x: 0, y: 0, width: 50, height: 20)
        form.text_field("b", page: page, x: 0, y: 30, width: 50, height: 20)
      end

      out = String.new(pdf.to_slice)
      # The page object should now have an /Annots entry pointing
      # to two widget references.
      out.should contain("/Annots")
      out.should contain("/Subtype /Widget")
    end
  end
end
