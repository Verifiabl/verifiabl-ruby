# frozen_string_literal: true

require_relative "generated/pii_text_profile"

module Verifiabl
  module Issuer
    module Pii
      FIELD_ORDER = %i[
        employee_name position department employer_abn bsb account_number account_name address
      ].freeze
      PROFILE_ID = PiiTextProfile::PROFILE_ID
      PROFILE_UNICODE_VERSION = PiiTextProfile::UNICODE_VERSION
      PAYLOAD_MAX_BYTES = PiiTextProfile::PAYLOAD_MAX_BYTES
      FORMAT_CHARACTER_RANGES = PiiTextProfile::FORMAT_CHARACTER_RANGES

      Violation = Data.define(:field, :reason)

      class ValidationError < ArgumentError
        attr_reader :violations

        def initialize(violations)
          @violations = violations.freeze
          details = violations.map { |violation| "#{violation.field} #{description(violation.reason)}" }.join("; ")
          super("Invalid PII field#{"s" unless violations.one?}: #{details}")
        end

        private

        def description(reason)
          {
            pipe: "must not contain '|'",
            control_character: "must not contain control characters or line separators",
            format_character: "must not contain format characters",
            invalid_unicode: "must contain valid Unicode"
          }.fetch(reason)
        end
      end

      module_function

      # Formats employee PII into the current P2 plaintext wire format. The
      # returned value must be encrypted before it is persisted or embedded.
      def format(fields)
        validate_fields!(fields)
        values, violations = normalize_values(fields)
        raise ValidationError, violations unless violations.empty?

        plaintext = "P2|#{FIELD_ORDER.map { |field| values.fetch(field) }.join("|")}"
        raise RangeError, "P2 plaintext exceeds #{PAYLOAD_MAX_BYTES} UTF-8 bytes" if plaintext.bytesize > PAYLOAD_MAX_BYTES
        plaintext
      end

      def validate_fields!(fields)
        raise ArgumentError, "fields must be a Hash" unless fields.is_a?(Hash)

        normalized_keys = fields.keys.map do |key|
          raise ArgumentError, "PII field names must be strings or symbols" unless key.is_a?(String) || key.is_a?(Symbol)
          key.to_sym
        end
        unknown = normalized_keys - FIELD_ORDER
        raise ArgumentError, "unknown PII field: #{unknown.first}" unless unknown.empty?
      end
      private_class_method :validate_fields!

      def normalize_values(fields)
        values = {}
        violations = []
        FIELD_ORDER.each do |field|
          value, violation = normalize_value(field, field_value(fields, field))
          values[field] = value
          violations << violation if violation
        end
        [values, violations]
      end
      private_class_method :normalize_values

      def field_value(fields, field)
        if fields.key?(field)
          fields[field]
        elsif fields.key?(field.to_s)
          fields[field.to_s]
        end
      end
      private_class_method :field_value

      def normalize_value(field, raw)
        raise ArgumentError, "#{field} must be a String" unless raw.nil? || raw.is_a?(String)

        value = raw.nil? ? "" : utf8(raw)
        reason = violation_reason(value)
        [value, reason && Violation.new(field:, reason:)]
      rescue EncodingError
        ["", Violation.new(field:, reason: :invalid_unicode)]
      end
      private_class_method :normalize_value

      def utf8(value)
        converted = if value.encoding == Encoding::BINARY
          value.dup.force_encoding(Encoding::UTF_8)
        else
          value.encode(Encoding::UTF_8)
        end
        raise EncodingError, "invalid Unicode" unless converted.valid_encoding?

        converted
      rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
        raise EncodingError, "invalid Unicode"
      end
      private_class_method :utf8

      def violation_reason(value)
        return :invalid_unicode unless value.valid_encoding?
        return :pipe if value.include?("|")
        return :control_character if value.codepoints.any? { |codepoint| control_character?(codepoint) }
        :format_character if value.codepoints.any? { |codepoint| format_character?(codepoint) }
      end
      private_class_method :violation_reason

      def control_character?(codepoint)
        codepoint <= 0x1f || codepoint.between?(0x7f, 0x9f) || [0x2028, 0x2029].include?(codepoint)
      end
      private_class_method :control_character?

      def format_character?(codepoint)
        FORMAT_CHARACTER_RANGES.any? { |first, last| codepoint.between?(first, last) }
      end
      private_class_method :format_character?
    end
  end
end
