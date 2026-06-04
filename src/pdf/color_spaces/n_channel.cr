module PDF
  module ColorSpaces
    # NChannel colour space (PDF spec § 8.6.6.5) — a specialised
    # `DeviceN` whose attributes dictionary carries `/Subtype
    # /NChannel`. It is the modern form for spaces that mix process
    # inks with one or more spot colorants : the optional `/Process`
    # entry names the process colour space and which colorants feed
    # it, letting a conforming renderer composite spot and process
    # colours correctly rather than only through the shared tint
    # transform.
    #
    # Array form (identical to DeviceN, the attributes dictionary is
    # always present) :
    # `[/DeviceN [/n1 /n2 ...] <alternate> <tintTransform> <attributes>]`
    # with `<attributes>` = `<< /Subtype /NChannel /Colorants << … >>
    # [/Process << … >>] >>`.
    #
    # ## Spot colorants and PDF/A-2 § 6.2.4.4
    #
    # NChannel is subject to the same `/Colorants` requirement as
    # `DeviceN` : every spot colorant must have an entry. That logic
    # is inherited from `DeviceN` ; this class only adds `/Subtype
    # /NChannel` and the optional `/Process` description.
    #
    # ## Example
    #
    # ```
    # # CMYK process + one spot ink, all over a FOGRA39 fallback.
    # nchan = PDF::ColorSpaces::NChannel.new(
    #   names: ["Cyan", "Magenta", "Yellow", "Black", "Pantone 877 C"],
    #   alternate: PDF::ColorSpaces::ICCBased.fogra39,
    #   c1_per_component: [
    #     [1.0, 0.0, 0.0, 0.0],
    #     [0.0, 1.0, 0.0, 0.0],
    #     [0.0, 0.0, 1.0, 0.0],
    #     [0.0, 0.0, 0.0, 1.0],
    #     [0.0, 0.0, 0.0, 0.2], # spot
    #   ],
    #   process_components: ["Cyan", "Magenta", "Yellow", "Black"],
    # )
    # ```
    class NChannel < DeviceN
      # Names of the colorants that feed the process colour space, in
      # channel order (e.g. `["Cyan", "Magenta", "Yellow", "Black"]`).
      # `nil` = no `/Process` entry emitted. When given, the process
      # colour space is this space's `alternate`, so the list length
      # must equal `alternate.num_components` and every name must also
      # appear in `names`.
      getter process_components : Array(String)?

      def initialize(
        *,
        names : Array(String),
        alternate : ICCBased,
        c1_per_component : Array(Array(Float64)),
        @process_components : Array(String)? = nil,
      )
        super(names: names, alternate: alternate, c1_per_component: c1_per_component)
        if components = @process_components
          unless components.size == @alternate.num_components
            raise ArgumentError.new("NChannel /Process needs #{@alternate.num_components} component name(s) to match the #{@alternate.num_components}-channel alternate")
          end
          missing = components.reject { |c| @names.includes?(c) }
          unless missing.empty?
            raise ArgumentError.new("NChannel /Process components #{missing} are not among the colorant names")
          end
        end
      end

      # Extends `DeviceN`'s attributes (the `/Colorants` dictionary,
      # built only when spot colorants are present) with the
      # `/Subtype /NChannel` marker — always emitted, so an NChannel
      # always carries an attributes dictionary — and the optional
      # `/Process` sub-dictionary.
      private def build_attributes(alternate_ref : Objects::Reference) : Objects::Dictionary?
        attributes = super || Objects::Dictionary.new
        attributes["Subtype"] = Objects::Name.new("NChannel")

        if components = @process_components
          process = Objects::Dictionary.new
          process["ColorSpace"] = ColorSpaces.icc_based_space(alternate_ref)
          component_names = Objects::Array.new
          components.each { |n| component_names << Objects::Name.new(n) }
          process["Components"] = component_names
          attributes["Process"] = process
        end

        attributes
      end
    end
  end
end
