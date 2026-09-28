# frozen_string_literal: true

module Verifiabl
  module Issuer
    AUSTRALIAN_PAYSLIP_V2_SCHEMA = "au.payslip.v2"
    NEW_ZEALAND_PAYSLIP_V2_SCHEMA = "nz.payslip.v2"
    SUPPORTED_V2_CURRENCIES = %w[AUD NZD USD GBP EUR CAD SGD HKD CHF ZAR].freeze

    module PayslipV2
      DECIMAL_PATTERN = /\A-?[0-9]+(?:\.[0-9]+)?\z/
      EXPONENT_PATTERN = /\A(-?)([0-9]+)\.([0-9]+)e([+-][0-9]+)\z/

      module_function

      def number(value, display: nil)
        encoded = decimal_string(value)
        raise ArgumentError, "value must be a decimal number, for example 1234.56" unless DECIMAL_PATTERN.match?(encoded)
        valid_display = display.nil? || display.is_a?(String) && !display.empty?
        raise ArgumentError, "display must be a non-empty String" unless valid_display

        {value: encoded, **(display.nil? ? {} : {display:})}
      end

      def decimal_string(value)
        case value
        when String
          value
        when Integer
          value.to_s
        when Float
          expand_exponent(value.to_s)
        else
          # BigDecimal#to_s defaults to engineering notation, for example "0.15e1".
          return value.to_s("F") if defined?(::BigDecimal) && value.is_a?(::BigDecimal)

          raise ArgumentError, "value must be a String, Integer, Float or BigDecimal"
        end
      end
      private_class_method :decimal_string

      # Float#to_s switches to exponent form for large and small magnitudes, for example "1.0e-05".
      def expand_exponent(text)
        match = EXPONENT_PATTERN.match(text)
        return text unless match

        sign, whole, fraction, exponent = match.captures
        digits = whole + fraction.sub(/0+\z/, "")
        point = whole.length + exponent.to_i
        if point <= 0
          "#{sign}0.#{"0" * -point}#{digits}"
        elsif point >= digits.length
          "#{sign}#{digits}#{"0" * (point - digits.length)}"
        else
          "#{sign}#{digits[0, point]}.#{digits[point..]}"
        end
      end
      private_class_method :expand_exponent
    end
  end
end
