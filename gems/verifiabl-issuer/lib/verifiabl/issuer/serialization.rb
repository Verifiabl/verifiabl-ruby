# frozen_string_literal: true

require "base64"

module Verifiabl
  module Issuer
    # Translation helpers for the issuer API's JSON wire shape. Ruby callers use
    # snake_case symbols; wire hashes use string keys and never mutate inputs.
    module Serialization
      module_function

      def registration_to_wire(schema:, issued_at:, payslip_non_pii:, encryption_metadata:)
        Validation.registration!(schema: schema, issued_at: issued_at, payslip_non_pii: payslip_non_pii, encryption_metadata: encryption_metadata)
        {
          "schema" => schema,
          "issued_at" => serialize_time(issued_at),
          "payslip_non_pii" => stringify_keys(payslip_non_pii),
          "encryption_metadata" => encryption_metadata_to_wire(encryption_metadata)
        }
      end

      def register_and_build_barcode_to_wire(encrypted_pii:, **registration)
        Validation.ciphertext!(encrypted_pii)
        registration_to_wire(**registration).merge("encrypted_pii" => encode64(encrypted_pii))
      end

      def batch_to_wire(records:)
        raise ArgumentError, "records must contain between 1 and 1000 records" unless records.is_a?(Array) && records.length.between?(1, 1000)

        {"records" => records.each_with_index.map { |record, index| batch_record_to_wire(record, index) }}
      end

      def batch_record_to_wire(record, index)
        raise ArgumentError, "records[#{index}] must be a Hash" unless record.is_a?(Hash)

        reference = fetch(record, :verifiabl_reference)
        Validation.reference!(reference)
        wire = registration_to_wire(
          schema: fetch(record, :schema),
          issued_at: fetch(record, :issued_at),
          payslip_non_pii: fetch(record, :payslip_non_pii),
          encryption_metadata: fetch(record, :encryption_metadata)
        ).merge("verifiabl_reference" => reference)
        if record.key?(:external_id) || record.key?("external_id")
          external_id = fetch(record, :external_id)
          wire["external_id"] = Validation.external_id!(external_id)
        end
        wire
      end
      private_class_method :batch_record_to_wire

      def serialize_time(value)
        return value unless value.is_a?(Time)

        value.utc.iso8601(3)
      end
      private_class_method :serialize_time

      def encryption_metadata_to_wire(metadata)
        wire = stringify_keys(metadata)
        wire["iv"] = encode64(wire.fetch("iv"))
        wire["tag"] = encode64(wire.fetch("tag"))
        wire
      end
      private_class_method :encryption_metadata_to_wire

      def encode64(value)
        Base64.urlsafe_encode64(value, padding: false)
      end
      private_class_method :encode64

      def fetch(hash, key)
        return hash[key] if hash.key?(key)
        return hash[key.to_s] if hash.key?(key.to_s)

        raise ArgumentError, "#{key} is required"
      end
      private_class_method :fetch

      def stringify_keys(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, child), wire|
            string_key = key.to_s
            raise ArgumentError, "duplicate key after string normalization: #{string_key}" if wire.key?(string_key)

            wire[string_key] = stringify_keys(child)
          end
        when Array
          value.map { |child| stringify_keys(child) }
        else
          value
        end
      end
      private_class_method :stringify_keys
    end
  end
end
