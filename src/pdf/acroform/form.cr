module PDF
  module AcroForm
    # The document's interactive form — root `/AcroForm` dict in
    # the catalog (PDF spec § 12.7.2).
    #
    # An AcroForm collects top-level fields (text, checkboxes, radio
    # groups, dropdowns) and emits the `/AcroForm` dictionary at
    # write time. The MVP uses `/NeedAppearances true` so visualizers
    # (Acrobat, Preview, PDF.js) generate appearance streams on the
    # fly when the user fills the form ; appearance streams written
    # by the library will come in J1.
    #
    # ```
    # pdf.acroform do |form|
    #   form.text_field("nom", page: page, x: 100, y: 700, width: 200, height: 20)
    #   form.checkbox("rgpd", page: page, x: 100, y: 650)
    # end
    # ```
    class Form
      getter document : Document
      getter fields : Array(Field) = [] of Field

      # Default appearance string applied to fields without their
      # own `/DA`. Format : `/<font-resource> <size> Tf <colorspace> <fill>`.
      property default_appearance : String = "/Helv 0 Tf 0 g"

      def initialize(@document : Document)
      end

      # Adds a single-line or multi-line text field.
      def text_field(
        name : String,
        *,
        page : Page,
        x : Number,
        y : Number,
        width : Number,
        height : Number,
        value : String? = nil,
        default_value : String? = nil,
        max_length : Int32? = nil,
        multiline : Bool = false,
        password : Bool = false,
        alignment : Symbol = :left,
        required : Bool = false,
        read_only : Bool = false,
        no_export : Bool = false,
      ) : TextField
        rect = {x.to_f, y.to_f, x.to_f + width.to_f, y.to_f + height.to_f}
        field = TextField.new(
          name: name,
          page: page,
          rect: rect,
          value: value,
          default_value: default_value,
          max_length: max_length,
          multiline: multiline,
          password: password,
          alignment: alignment,
        )
        field.required = required
        field.read_only = read_only
        field.no_export = no_export
        add(field)
        field
      end

      # Adds a checkbox.
      def checkbox(
        name : String,
        *,
        page : Page,
        x : Number,
        y : Number,
        size : Number = 12,
        checked : Bool = false,
        required : Bool = false,
        read_only : Bool = false,
        no_export : Bool = false,
      ) : Checkbox
        s = size.to_f
        rect = {x.to_f, y.to_f, x.to_f + s, y.to_f + s}
        field = Checkbox.new(
          name: name,
          page: page,
          rect: rect,
          checked: checked,
        )
        field.required = required
        field.read_only = read_only
        field.no_export = no_export
        add(field)
        field
      end

      # Adds a radio button group. `options` may be an `Array(String)`
      # (each entry is both the export code and the label hint) or a
      # `Hash(String, String)` mapping code => label. Only the codes
      # are embedded in the PDF widget; the caller positions labels
      # separately.
      def radio_group(
        name : String,
        *,
        page : Page,
        options : Array(String) | Hash(String, String),
        x : Number,
        y : Number,
        spacing : Number = 20,
        size : Number = 12,
        selected : String? = nil,
        no_toggle_to_off : Bool = true,
        required : Bool = false,
        read_only : Bool = false,
        no_export : Bool = false,
      ) : RadioGroup
        field = RadioGroup.new(
          name: name,
          page: page,
          options: options,
          origin: {x.to_f, y.to_f},
          spacing: spacing.to_f,
          size: size.to_f,
          selected: selected,
          no_toggle_to_off: no_toggle_to_off,
        )
        field.required = required
        field.read_only = read_only
        field.no_export = no_export
        add(field)
        field
      end

      # Adds a dropdown (combo box). `options` may be an
      # `Array(String)` (export = display) or a `Hash(String, String)`
      # mapping export code => display label. The Hash form emits
      # `/Opt` as a list of two-element arrays.
      def dropdown(
        name : String,
        *,
        page : Page,
        options : Array(String) | Hash(String, String),
        x : Number,
        y : Number,
        width : Number,
        height : Number,
        value : String? = nil,
        default_value : String? = nil,
        editable : Bool = false,
        required : Bool = false,
        read_only : Bool = false,
        no_export : Bool = false,
      ) : Dropdown
        rect = {x.to_f, y.to_f, x.to_f + width.to_f, y.to_f + height.to_f}
        field = Dropdown.new(
          name: name,
          page: page,
          rect: rect,
          options: options,
          value: value,
          default_value: default_value,
          editable: editable,
        )
        field.required = required
        field.read_only = read_only
        field.no_export = no_export
        add(field)
        field
      end

      # Adds a listbox (multi-selection choice field). `options`
      # may be an `Array(String)` or a `Hash(String, String)` (same
      # rules as `#dropdown`). `value` and `default_value` are arrays
      # of selected codes.
      def listbox(
        name : String,
        *,
        page : Page,
        options : Array(String) | Hash(String, String),
        x : Number,
        y : Number,
        width : Number,
        height : Number,
        value : Array(String)? = nil,
        default_value : Array(String)? = nil,
        sort : Bool = false,
        required : Bool = false,
        read_only : Bool = false,
        no_export : Bool = false,
      ) : Listbox
        rect = {x.to_f, y.to_f, x.to_f + width.to_f, y.to_f + height.to_f}
        field = Listbox.new(
          name: name,
          page: page,
          rect: rect,
          options: options,
          value: value,
          default_value: default_value,
          sort: sort,
        )
        field.required = required
        field.read_only = read_only
        field.no_export = no_export
        add(field)
        field
      end

      # Registers a field and attaches its widget to the page.
      # RadioGroup is a special case : its parent dict is *not* a
      # widget annotation, only its kids are — the kids are attached
      # to the page from within `RadioGroup#configure`.
      private def add(field : Field) : Nil
        # Unicity check on field name.
        if @fields.any? { |f| f.name == field.name }
          raise ArgumentError.new("Field '#{field.name}' already declared in this form")
        end

        @fields << field
      end

      # Builds the /AcroForm dictionary, registers each top-level
      # field as an indirect object, attaches widget annotations to
      # pages, and returns the indirect reference to be stored in
      # the catalog. Called by `Document#build_catalog`.
      def finalize! : Objects::Reference
        # Ensure Helvetica is loaded (used by /DR and /DA).
        helv = @document.font("Helvetica")
        helv_dict = helv.to_dictionary
        helv_obj = @document.register_object(helv_dict)

        # Build /DR (default resources) : a /Font sub-dict that maps
        # the name used in /DA (here `/Helv`) to a font reference.
        font_dict = Objects::Dictionary.new
        font_dict["Helv"] = helv_obj.reference

        dr = Objects::Dictionary.new
        dr["Font"] = font_dict

        # Build /Fields array. Each field's combined dict is
        # registered ; for non-RadioGroup fields, the resulting
        # reference is also added to the page's /Annots.
        #
        # RadioGroup needs its parent object ID *before* `field.dict`
        # is built, so kid widgets can carry `/Parent <id 0 R>`.
        # Other fields are registered the regular way.
        fields_array = Objects::Array.new
        @fields.each do |field|
          if field.is_a?(RadioGroup)
            parent_id = @document.allocate_object_id
            field.parent_object_id = parent_id
            field_dict = field.dict
            field_obj = Objects::Indirect.new(parent_id, field_dict)
            @document.objects << field_obj
            fields_array << field_obj.reference
            # Kids are attached to the page from within
            # `RadioGroup#configure` — the parent itself is not a
            # widget annotation.
          else
            field_obj = @document.register_object(field.dict)
            fields_array << field_obj.reference
            field.page.add_annotation_ref(field_obj.reference)
          end
        end

        # Build /AcroForm dict.
        acroform = Objects::Dictionary.new
        acroform["Fields"] = fields_array
        acroform["NeedAppearances"] = Objects::Boolean.new(true)
        acroform["DA"] = Objects::Str.new(@default_appearance)
        acroform["DR"] = dr

        acroform_obj = @document.register_object(acroform)
        acroform_obj.reference
      end
    end
  end
end
