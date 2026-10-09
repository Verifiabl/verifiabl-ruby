# frozen_string_literal: true

require_relative "generated/pii_text_profile"
require_relative "generated/jurisdiction_pii_profiles"

module Verifiabl
  module Issuer
    module Pii
      AUSTRALIAN_FIELD_ORDER = JurisdictionPiiProfiles::AUSTRALIAN_FIELD_ORDER
      NEW_ZEALAND_FIELD_ORDER = JurisdictionPiiProfiles::NEW_ZEALAND_FIELD_ORDER
      AUSTRALIAN_PROFILE_ID = JurisdictionPiiProfiles::AUSTRALIAN_PROFILE_ID
      NEW_ZEALAND_PROFILE_ID = JurisdictionPiiProfiles::NEW_ZEALAND_PROFILE_ID
      PROFILE_UNICODE_VERSION = PiiTextProfile::UNICODE_VERSION
      PAYLOAD_MAX_BYTES = JurisdictionPiiProfiles::PAYLOAD_MAX_BYTES
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

      # Formats Australian employee PII as AU2 plaintext. The returned value
      # must be encrypted before it is persisted or embedded.
      def format_australian(fields)
        allowed = %i[
          employee_name position department employer_name employer_abn bsb account_number account_name address
        ]
        validate_fields!(fields, allowed)
        values, violations = normalize_named_values(fields, allowed - [:address])
        address, address_violations = australian_address(field_value(fields, :address))
        violations.concat(address_violations)
        raise ValidationError, violations unless violations.empty?

        employer_identity = values.fetch(:employer_abn)
        employer_identity = values.fetch(:employer_name) if employer_identity.empty?
        wire_values = values.merge(employer_identity: employer_identity, address: address)
        format_profile(JurisdictionPiiProfiles::AUSTRALIAN_MARKER, AUSTRALIAN_FIELD_ORDER.map { |field| wire_values.fetch(field) })
      end

      # Formats New Zealand employee PII as NZ2 plaintext. The returned value
      # must be encrypted before it is persisted or embedded.
      def format_new_zealand(fields)
        allowed = %i[
          employee_name ird_number position department employer_name account_number account_name address
        ]
        validate_fields!(fields, allowed)
        values, violations = normalize_named_values(fields, allowed - [:address])
        address, address_violations = new_zealand_address(field_value(fields, :address))
        violations.concat(address_violations)
        raise ValidationError, violations unless violations.empty?

        wire_values = values.merge(address: address)
        format_profile(JurisdictionPiiProfiles::NEW_ZEALAND_MARKER, NEW_ZEALAND_FIELD_ORDER.map { |field| wire_values.fetch(field) })
      end

      def validate_fields!(fields, allowed)
        raise ArgumentError, "fields must be a Hash" unless fields.is_a?(Hash)

        normalized_keys = fields.keys.map do |key|
          raise ArgumentError, "PII field names must be strings or symbols" unless key.is_a?(String) || key.is_a?(Symbol)
          key.to_sym
        end
        unknown = normalized_keys - allowed
        raise ArgumentError, "unknown PII field: #{unknown.first}" unless unknown.empty?
      end
      private_class_method :validate_fields!

      def normalize_named_values(fields, names)
        names.each_with_object([{}, []]) do |field, (values, violations)|
          value, violation = normalize_value(field, field_value(fields, field))
          values[field] = value
          violations << violation if violation
        end
      end
      private_class_method :normalize_named_values

      def australian_address(raw)
        address(raw, %i[lines suburb state_or_territory postcode]) do |values|
          locality = compact_join(
            [values.fetch(:suburb), values.fetch(:state_or_territory), values.fetch(:postcode)],
            " "
          )
          compact_join([*values.fetch(:lines), locality], ", ")
        end
      end
      private_class_method :australian_address

      def new_zealand_address(raw)
        address(raw, %i[lines suburb city postcode]) do |values|
          city = compact_join([values.fetch(:city), values.fetch(:postcode)], " ")
          compact_join([*values.fetch(:lines), values.fetch(:suburb), city], ", ")
        end
      end
      private_class_method :new_zealand_address

      def address(raw, allowed)
        return ["", []] if raw.nil?

        validate_fields!(raw, allowed)
        lines = field_value(raw, :lines)
        raise ArgumentError, "address.lines must be an Array" unless lines.nil? || lines.is_a?(Array)

        violations = []
        normalized_lines = (lines || []).map do |line|
          value, violation = normalize_value(:address, line)
          violations << violation if violation
          value
        end
        values, field_violations = normalize_named_values(raw, allowed - [:lines])
        violations.concat(field_violations)
        values[:lines] = normalized_lines
        [yield(values), violations]
      end
      private_class_method :address

      def compact_join(values, delimiter)
        values.reject(&:empty?).join(delimiter)
      end
      private_class_method :compact_join

      def format_profile(version, segments)
        plaintext = "#{version}|#{segments.join("|")}"
        if plaintext.bytesize > PAYLOAD_MAX_BYTES
          raise RangeError, "#{version} plaintext exceeds #{PAYLOAD_MAX_BYTES} UTF-8 bytes"
        end

        plaintext
      end
      private_class_method :format_profile

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
