# frozen_string_literal: true

require "date"
require "time"

module Verifiabl
  module Issuer
    module Validation
      SCHEMA_PATTERN = /\A[a-z]{2}\.[a-z]+\.v[0-9]+\z/
      REFERENCE_PATTERN = /\A[A-Za-z0-9_-]{22}\z/
      EXTERNAL_ID_PATTERN = /\A[\x20-\x7e]+\z/

      module_function

      def registration!(schema:, issued_at:, payslip_non_pii:, encryption_metadata:)
        raise ArgumentError, "schema must be in format 'xx.type.vN'" unless schema.is_a?(String) && SCHEMA_PATTERN.match?(schema)
        validate_issued_at!(issued_at)
        raise ArgumentError, "payslip_non_pii must be a Hash" unless payslip_non_pii.is_a?(Hash)
        validate_iso_date!(value(payslip_non_pii, :period_start), "period_start") if key?(payslip_non_pii, :period_start)
        validate_iso_date!(value(payslip_non_pii, :period_end), "period_end") if key?(payslip_non_pii, :period_end)
        validate_encryption_metadata!(encryption_metadata)
      end

      def reference!(reference)
        raise ArgumentError, "verifiabl_reference must be exactly 22 base64url characters" unless reference.is_a?(String) && REFERENCE_PATTERN.match?(reference)

        reference
      end

      def ciphertext!(ciphertext)
        valid = ciphertext.is_a?(String) && ciphertext.encoding == Encoding::BINARY && ciphertext.bytesize.between?(1, 7_500)
        raise ArgumentError, "encrypted_pii must be a binary string containing between 1 and 7500 bytes" unless valid

        ciphertext
      end

      def external_id!(external_id)
        valid = external_id.is_a?(String) && external_id.length.between?(1, 255) && EXTERNAL_ID_PATTERN.match?(external_id)
        raise ArgumentError, "external_id must be 1-255 printable ASCII characters" unless valid

        external_id
      end

      def validate_encryption_metadata!(metadata)
        raise ArgumentError, "encryption_metadata must be a Hash" unless metadata.is_a?(Hash)

        iv = value(metadata, :iv)
        tag = value(metadata, :tag)
        valid_iv = iv.is_a?(String) && iv.encoding == Encoding::BINARY && iv.bytesize == 12
        valid_tag = tag.is_a?(String) && tag.encoding == Encoding::BINARY && tag.bytesize == 16
        raise ArgumentError, "encryption_metadata.iv must be a 12-byte binary string (96-bit IV)" unless valid_iv
        raise ArgumentError, "encryption_metadata.tag must be a 16-byte binary string (128-bit GCM tag)" unless valid_tag
      end
      private_class_method :validate_encryption_metadata!

      def validate_issued_at!(issued_at)
        return if issued_at.is_a?(Time)

        valid = issued_at.is_a?(String) && issued_at.end_with?("Z") && Time.iso8601(issued_at).utc?
        raise ArgumentError, "issued_at must be an ISO 8601 UTC timestamp ending in Z" unless valid
      rescue ArgumentError
        raise ArgumentError, "issued_at must be an ISO 8601 UTC timestamp ending in Z"
      end
      private_class_method :validate_issued_at!

      def validate_iso_date!(date, name)
        valid = date.is_a?(String) && date.match?(/\A\d{4}-\d{2}-\d{2}\z/) && Date.iso8601(date)
        raise ArgumentError, "#{name} must be a YYYY-MM-DD date" unless valid
      rescue Date::Error
        raise ArgumentError, "#{name} must be a YYYY-MM-DD date"
      end
      private_class_method :validate_iso_date!

      def key?(hash, key)
        hash.key?(key) || hash.key?(key.to_s)
      end
      private_class_method :key?

      def value(hash, key)
        hash.key?(key) ? hash[key] : hash[key.to_s]
      end
      private_class_method :value
    end
  end
end
