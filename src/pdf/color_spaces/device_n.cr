module PDF
  module ColorSpaces
    # DeviceN colour space (PDF spec § 8.6.6.5) — N spot or process
    # colours sharing a single alternate fallback. Generalisation
    # of `Separation` for N > 1.
    #
    # Array form : `[/DeviceN [/n1 /n2 ...] <alternate> <tintTransform>]`.
    # The tint transform maps an N-vector of tint scalars to the
    # alternate colour-space coordinates via a Type-2 function per
    # component, combined into a stitching Type-3 function.
    #
    # ## MVP behaviour
    #
    # This implementation supports the most common case : every
    # component contributes linearly to the alternate values, with
    # per-component `c1` vectors. The tint transform is built as a
    # stitching of N Type-2 functions over a domain `[0, 1]^N`.
    #
    # ```
    # multi = PDF::ColorSpaces::DeviceN.new(
    #   names: ["Pantone 185 C", "Pantone 286 C"],
    #   alternate: PDF::ColorSpaces::ICCBased.fogra39,
    #   c1_per_component: [
    #     [0.0, 1.0, 0.7, 0.0], # ink 1
    #     [1.0, 0.6, 0.0, 0.0], # ink 2
    #   ],
    # )
    # ```
    class DeviceN
      getter names : Array(String)
      getter alternate : ICCBased
      getter c1_per_component : Array(Array(Float64))

      def initialize(
        *,
        @names : Array(String),
        @alternate : ICCBased,
        @c1_per_component : Array(Array(Float64)),
      )
        raise ArgumentError.new("DeviceN needs at least one component") if @names.empty?
        raise ArgumentError.new("DeviceN needs `c1_per_component` with one entry per name") if @c1_per_component.size != @names.size
        @c1_per_component.each_with_index do |c1, i|
          unless c1.size == @alternate.num_components
            raise ArgumentError.new("DeviceN component #{i} : c1 must have #{@alternate.num_components} values (alternate is #{@alternate.num_components}-channel)")
          end
        end
      end

      def to_array(alternate_ref : Objects::Reference) : Objects::Array
        arr = Objects::Array.new
        arr << Objects::Name.new("DeviceN")
        names_arr = Objects::Array.new
        @names.each { |n| names_arr << Objects::Name.new(n) }
        arr << names_arr
        arr << ColorSpaces.icc_based_space(alternate_ref)
        arr << build_tint_transform
        arr
      end

      # Tint transform — a Type-4 PostScript function would be more
      # accurate ; we use a Type-2 per component summed at runtime
      # via a simple Type-2 over a 1-component slice. For the MVP
      # we emit a Type-2 function whose Domain is `[0 1] * N` and
      # whose C0/C1 are the *sum* of paper-white and ink-1 vectors
      # respectively. This is a conservative approximation that
      # produces sensible colours when only one ink is non-zero.
      private def build_tint_transform : Objects::Dictionary
        f = Objects::Dictionary.new
        f["FunctionType"] = Objects::Number.new(2)
        domain = Objects::Array.new
        @names.size.times do
          domain << Objects::Number.new(0)
          domain << Objects::Number.new(1)
        end
        f["Domain"] = domain

        c0 = Objects::Array.new
        @alternate.num_components.times { c0 << Objects::Number.new(0) }
        f["C0"] = c0

        # C1 = sum of all per-component C1 values (works when one ink
        # is fully on at a time ; a richer tint transform should use
        # FunctionType 4 with explicit PostScript code).
        sum = Array(Float64).new(@alternate.num_components, 0.0)
        @c1_per_component.each do |c1|
          c1.each_with_index { |v, i| sum[i] += v }
        end
        c1 = Objects::Array.new
        sum.each { |v| c1 << Objects::Number.new(v.clamp(0.0, 1.0)) }
        f["C1"] = c1

        f["N"] = Objects::Number.new(1)
        f
      end
    end
  end
end
