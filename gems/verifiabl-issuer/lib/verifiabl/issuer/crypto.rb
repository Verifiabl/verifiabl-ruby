# frozen_string_literal: true

require "openssl"
require "securerandom"

module Verifiabl
  module Issuer
    module Crypto
      KEY_BYTES = 32
      IV_BYTES = 12

      EncryptedPii = Data.define(:encrypted_pii, :encryption_metadata) do
        def to_h
          {encrypted_pii:, encryption_metadata:}
        end
      end

      module_function

      # Encrypts formatted PII with AES-256-GCM and a fresh 96-bit IV.
      def encrypt(plaintext, key)
        validate!(plaintext, key)

        iv = SecureRandom.random_bytes(IV_BYTES)
        cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
        cipher.key = key
        cipher.iv = iv
        ciphertext = cipher.update(plaintext.encode(Encoding::UTF_8)) + cipher.final

        EncryptedPii.new(
          encrypted_pii: ciphertext,
          encryption_metadata: {
            iv: iv,
            tag: cipher.auth_tag
          }.freeze
        )
      end

      def validate!(plaintext, key)
        raise ArgumentError, "plaintext must be a String" unless plaintext.is_a?(String)
        raise ArgumentError, "encryption key must be exactly 32 bytes (AES-256)" unless key.is_a?(String) && key.bytesize == KEY_BYTES
      end
      private_class_method :validate!
    end
  end
end
