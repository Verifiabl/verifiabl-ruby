# frozen_string_literal: true

require_relative "issuer/base32"
require_relative "issuer/configuration"
require_relative "issuer/errors"
require_relative "issuer/validation"
require_relative "issuer/responses"
require_relative "issuer/client"
require_relative "issuer/crypto"
require_relative "issuer/instrumentation"
require_relative "issuer/payload"
require_relative "issuer/payslip_v2"
require_relative "issuer/pii"
require_relative "issuer/qr"
require_relative "issuer/rendering"
require_relative "issuer/non_pii_v2"
require_relative "issuer/serialization"
require_relative "issuer/issuance"
require_relative "issuer/version"

module Verifiabl
  module Issuer
    class << self
      def format_pii(fields)
        Pii.format(fields)
      end

      def format_australian_pii(fields)
        Pii.format_australian(fields)
      end

      def format_new_zealand_pii(fields)
        Pii.format_new_zealand(fields)
      end

      def prepare_australian_v2_payslip(pii:, payslip_non_pii:, issued_at:, key:, verifiabl_reference: generate_verifiabl_reference)
        Issuance.prepare({pii:, payslip_non_pii:, issued_at:, key:, reference: verifiabl_reference},
          schema: AUSTRALIAN_PAYSLIP_V2_SCHEMA, formatter: :format_australian_pii)
      end

      def prepare_new_zealand_v2_payslip(pii:, payslip_non_pii:, issued_at:, key:, verifiabl_reference: generate_verifiabl_reference)
        Issuance.prepare({pii:, payslip_non_pii:, issued_at:, key:, reference: verifiabl_reference},
          schema: NEW_ZEALAND_PAYSLIP_V2_SCHEMA, formatter: :format_new_zealand_pii)
      end

      def encrypt_pii(plaintext, key)
        Crypto.encrypt(plaintext, key)
      end

      def generate_verifiabl_reference
        Payload.generate_reference
      end

      def build_barcode_payload(**options)
        Payload.build(**options)
      end

      def build_scan_url(**options)
        Payload.scan_url(**options)
      end

      def build_barcode_svg(**options)
        Rendering.svg(**options)
      end

      def build_barcode_png(**options)
        Rendering.png(**options)
      end
    end
  end
end
