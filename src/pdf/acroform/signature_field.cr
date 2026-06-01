module PDF
  module AcroForm
    # Signature field — `/FT /Sig` (PDF spec § 12.7.4.5). Declares
    # a slot for a digital signature on the page ; the cryptographic
    # signature itself (PKCS#7 / CMS / PAdES) is filled by
    # `aloli-crystal/pdf-signature` at signing time.
    #
    # Adding any signature field automatically sets `/SigFlags 3`
    # on `/AcroForm` (bit 1 = SignaturesExist, bit 2 = AppendOnly) :
    # this prevents viewers from "saving" the document in a way
    # that would invalidate downstream signatures.
    #
    # ```
    # form.signature_field("contract_sig", page: page, x: 100, y: 100, width: 200, height: 80)
    # ```
    #
    # The widget renders as an empty rectangle until the field is
    # signed ; Acrobat and Preview overlay their own "Sign here"
    # affordance on top.
    class SignatureField < Field
      def initialize(
        name : String,
        page : Page,
        rect : Tuple(Float64, Float64, Float64, Float64),
      )
        super(name, page, rect)
      end

      protected def field_type_name : String
        "Sig"
      end

      protected def configure(d : Objects::Dictionary) : Nil
        # /V remains absent until a signer fills it. The MVP does not
        # produce a placeholder signature dict — that's pdf-signature's
        # job at signing time.
      end
    end
  end
end
