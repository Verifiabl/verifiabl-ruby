# frozen_string_literal: true

require "json"

module Verifiabl
  module Issuer
    # A pre-transport privacy guard, not a second implementation of the API contract.
    module NonPiiV2
      FIELDS = JSON.parse(File.read(File.join(__dir__, "generated/non-pii-v2-fields.json"))).freeze

      module_function

      def validate!(schema, payload)
        check!(FIELDS.fetch(schema), payload, "payslip_non_pii")
      end

      def check!(allowed, value, path)
        case allowed
        when Hash
          raise ArgumentError, "#{path} must be an object" unless value.is_a?(Hash)

          value.each do |key, child|
            raise ArgumentError, "#{path}.#{key} is not permitted" unless allowed.key?(key)

            check!(allowed.fetch(key), child, "#{path}.#{key}")
          end
        when Array
          raise ArgumentError, "#{path} must be an array" unless value.is_a?(Array)

          value.each_with_index { |child, index| check!(allowed.first, child, "#{path}[#{index}]") }
        else
          check_scalar!(value, path)
        end
      end
      private_class_method :check!

      def check_scalar!(value, path)
        raise ArgumentError, "#{path} must be a scalar" if value.is_a?(Hash) || value.is_a?(Array)
      end
      private_class_method :check_scalar!
    end
  end
end
