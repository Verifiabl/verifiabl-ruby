# frozen_string_literal: true

require "base64"
require "securerandom"
require "uri"

module Verifiabl
  module Issuer
    module Payload
      REFERENCE_PATTERN = /\A[A-Za-z0-9_-]{22}\z/
      MAX_CIPHERTEXT_BYTES = 7_500
      PDF_PAYLOAD_XMP_NAMESPACE = "https://verifiabl.io/ns/"
      PDF_PAYLOAD_XMP_PROPERTY = "payload"

      ENVIRONMENTS = {
        production: {
          issuer_base_url: "https://register.verifiabl.io",
          scan_base_url: "https://v.verifiabl.io",
          token_url: "https://auth.verifiabl.io/oauth/token"
        }.freeze,
        sandbox: {
          issuer_base_url: "https://register.sandbox.verifiabl.io",
          scan_base_url: "https://v.sandbox.verifiabl.io",
          token_url: "https://auth.sandbox.verifiabl.io/oauth/token"
        }.freeze
      }.freeze

      ScanUrlParts = Data.define(:content, :byte_prefix, :alphanumeric_ciphertext)

      module_function

      def generate_reference
        Base64.urlsafe_encode64(SecureRandom.random_bytes(16), padding: false)
      end

      # Builds the payload copied into the PDF's XMP metadata.
      def build(verifiabl_reference:, encrypted_pii:)
        validate!(verifiabl_reference, encrypted_pii)
        ciphertext = Base32.encode(encrypted_pii)
        "2|#{verifiabl_reference}|#{ciphertext}"
      end

      def scan_url(**options)
        scan_url_parts(**options).content
      end

      # Returns the exact split consumed by a mixed-mode QR encoder: a byte
      # prefix followed by an alphanumeric Base32 ciphertext for v2.
      def scan_url_parts(verifiabl_reference:, encrypted_pii:, environment: :production, scan_base_url: nil)
        validate!(verifiabl_reference, encrypted_pii)
        origins = ENVIRONMENTS.fetch(normalize_environment(environment))
        base_url = normalize_scan_base_url(scan_base_url || origins.fetch(:scan_base_url))
        prefix = "#{base_url}/v/#{verifiabl_reference}#2."
        base32 = Base32.encode(encrypted_pii)
        ScanUrlParts.new(content: prefix + base32, byte_prefix: prefix, alphanumeric_ciphertext: base32)
      end

      def resolve_environment(environment)
        ENVIRONMENTS.fetch(normalize_environment(environment)).dup.freeze
      end

      def validate!(reference, ciphertext)
        raise ArgumentError, "Verifiabl reference must be exactly 22 base64url characters" unless reference.is_a?(String) && REFERENCE_PATTERN.match?(reference)
        valid_ciphertext = ciphertext.is_a?(String) && ciphertext.encoding == Encoding::BINARY && ciphertext.bytesize.between?(1, MAX_CIPHERTEXT_BYTES)
        raise ArgumentError, "ciphertext must be a binary string containing between 1 and 7500 bytes" unless valid_ciphertext
      end
      private_class_method :validate!

      def normalize_environment(environment)
        value = environment.respond_to?(:to_sym) ? environment.to_sym : nil
        return value if ENVIRONMENTS.key?(value)

        raise ArgumentError, "environment must be :production or :sandbox"
      end
      private_class_method :normalize_environment

      def normalize_scan_base_url(value)
        uri = URI.parse(value)
        raise ArgumentError, "scan_base_url must use https" unless uri.is_a?(URI::HTTPS) && uri.host

        default_port = (uri.port == 443) ? "" : ":#{uri.port}"
        "https://#{uri.host}#{default_port}"
      rescue URI::InvalidURIError
        raise ArgumentError, "invalid scan_base_url: #{value}"
      end
      private_class_method :normalize_scan_base_url
    end
  end
end
