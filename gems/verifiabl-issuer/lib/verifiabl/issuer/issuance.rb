# frozen_string_literal: true

module Verifiabl
  module Issuer
    # A single encryption and registration pair. Keep the reference and registration
    # together for self-managed retries; the API-managed endpoint allocates its own.
    class PreparedV2Payslip
      attr_reader :verifiabl_reference

      def initialize(reference:, registration:, encrypted:)
        @verifiabl_reference = reference.dup.freeze
        @registration = copy(registration, immutable: true)
        @encrypted_pii = encrypted.encrypted_pii.dup.freeze
      end

      # A mutable, independent self-managed registration request.
      def registration
        copy(@registration, immutable: false)
      end

      def api_managed_registration
        copy(@registration.except(:verifiabl_reference), immutable: false).merge(encrypted_pii: @encrypted_pii.dup)
      end

      def barcode_parts(reference)
        Validation.reference!(reference)
        {verifiabl_reference: reference.dup, encrypted_pii: @encrypted_pii.dup}
      end

      private

      def copy(value, immutable:)
        result = case value
        when Hash then value.transform_values { |child| copy(child, immutable:) }
        when Array then value.map { |child| copy(child, immutable:) }
        when String, Time then value.dup
        else value
        end
        immutable ? result.freeze : result
      end
    end

    module Issuance
      module_function

      def prepare(input, schema:, formatter:)
        pii, payslip_non_pii, issued_at, key, reference = input.values_at(:pii, :payslip_non_pii, :issued_at, :key, :reference)
        Validation.reference!(reference)
        # Reuse exactly the same envelope and closed v2 field tree used by the client.
        # Do this before formatting/encryption so a wrong-jurisdiction payload fails locally.
        placeholder = {iv: "\0".b * 12, tag: "\0".b * 16}
        Serialization.registration_to_wire(schema:, issued_at:, payslip_non_pii:, encryption_metadata: placeholder)
        plaintext = Issuer.public_send(formatter, pii)
        encrypted = Issuer.encrypt_pii(plaintext, key)
        registration = {schema:, issued_at:, payslip_non_pii:, encryption_metadata: encrypted.encryption_metadata, verifiabl_reference: reference}
        PreparedV2Payslip.new(reference:, registration:, encrypted:)
      end
    end
  end
end
