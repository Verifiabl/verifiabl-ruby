# frozen_string_literal: true

require "json"

module Verifiabl
  module Issuer
    # A pre-transport guard for unknown fields, the decimal grammar and AU2 lump sum codes, not a second
    # implementation of the API contract.
    module NonPiiV2
      FIELDS = JSON.parse(File.read(File.join(__dir__, "generated/non-pii-v2-fields.json"))).freeze
      DECIMAL_PATTERN = /\A-?[0-9]+(?:\.[0-9]+)?\z/

      module_function

      def validate!(schema, payload)
        check!(FIELDS.fetch(schema), payload, "payslip_non_pii")
        check_lump_sum_types!(payload) if schema == AUSTRALIAN_PAYSLIP_V2_SCHEMA
      end

      # The API still accepts a bare lump sum from older SDKs, but a lump sum without its STP2 code
      # cannot be categorised, so this SDK requires the code before sending.
      def check_lump_sum_types!(payload)
        Array(payload["earnings"]).each_with_index do |line, index|
          next unless line["type"] == "lump_sum" && line["lump_sum_type"].nil?

          raise ArgumentError, "payslip_non_pii.earnings[#{index}].lump_sum_type is required on a lump_sum line"
        end
      end
      private_class_method :check_lump_sum_types!

      def check!(allowed, value, path)
        case allowed
        when Hash then check_object!(allowed, value, path)
        when Array then check_array!(allowed.first, value, path)
        when "decimal" then check_decimal!(value, path)
        else check_scalar!(value, path)
        end
      end
      private_class_method :check!

      def check_object!(allowed, value, path)
        raise ArgumentError, "#{path} must be an object" unless value.is_a?(Hash)

        value.each do |key, child|
          raise ArgumentError, "#{path}.#{key} is not permitted" unless allowed.key?(key)

          check!(allowed.fetch(key), child, "#{path}.#{key}")
        end
      end
      private_class_method :check_object!

      def check_array!(allowed, value, path)
        raise ArgumentError, "#{path} must be an array" unless value.is_a?(Array)

        value.each_with_index { |child, index| check!(allowed, child, "#{path}[#{index}]") }
      end
      private_class_method :check_array!

      def check_decimal!(value, path)
        return if value.is_a?(String) && DECIMAL_PATTERN.match?(value)

        raise ArgumentError, "#{path} must be a plain decimal String, for example \"1234.56\""
      end
      private_class_method :check_decimal!

      def check_scalar!(value, path)
        raise ArgumentError, "#{path} must be a scalar" if value.is_a?(Hash) || value.is_a?(Array)
      end
      private_class_method :check_scalar!
    end
  end
end
