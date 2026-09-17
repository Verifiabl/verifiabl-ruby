# frozen_string_literal: true

module Verifiabl
  module Issuer
    module Base32
      ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

      module_function

      # Encodes bytes as canonical uppercase, unpadded RFC 4648 Base32.
      def encode(input)
        raise ArgumentError, "input must be a String" unless input.is_a?(String)

        output = +""
        accumulator = 0
        bits = 0
        input.b.each_byte { |byte| accumulator, bits = append_byte(output, accumulator, bits, byte) }
        output << ALPHABET[(accumulator << (5 - bits)) & 0x1f] if bits.positive?
        output
      end

      def append_byte(output, accumulator, bits, byte)
        accumulator = (accumulator << 8) | byte
        bits += 8
        while bits >= 5
          bits -= 5
          output << ALPHABET[(accumulator >> bits) & 0x1f]
        end
        [accumulator & ((1 << bits) - 1), bits]
      end
      private_class_method :append_byte
    end
  end
end
