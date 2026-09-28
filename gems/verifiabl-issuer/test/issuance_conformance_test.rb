# frozen_string_literal: true

require "json"
require_relative "test_helper"

class IssuanceConformanceTest < Minitest::Test
  FIXTURE = File.expand_path("fixtures/issuance-conformance-vectors-v1.json", __dir__)

  def test_matches_every_deterministic_issuance_stage_byte_for_byte
    vectors.fetch("valid").each do |vector|
      plaintext = Verifiabl::Issuer.format_pii(snake_case_fields(vector.fetch("fields")))
      assert_equal vector.fetch("plaintext"), plaintext, vector.fetch("id")
      assert_equal vector.fetch("plaintextUtf8Hex"), plaintext.unpack1("H*"), vector.fetch("id")

      encrypted = Verifiabl::Issuer::Crypto.send(
        :encrypt_with_iv,
        plaintext,
        decode_hex(vector.fetch("keyHex")),
        decode_hex(vector.fetch("ivHex"))
      )
      assert_equal vector.fetch("ciphertextHex"), encrypted.encrypted_pii.unpack1("H*"), vector.fetch("id")
      assert_equal vector.fetch("tagHex"), encrypted.encryption_metadata.fetch(:tag).unpack1("H*"), vector.fetch("id")
      assert_equal vector.fetch("ivHex"), encrypted.encryption_metadata.fetch(:iv).unpack1("H*"), vector.fetch("id")

      parts = {
        verifiabl_reference: vector.fetch("reference"),
        encrypted_pii: encrypted.encrypted_pii
      }
      assert_equal vector.fetch("xmpPayload"), Verifiabl::Issuer.build_barcode_payload(**parts), vector.fetch("id")
      assert_equal vector.fetch("productionScanUrl"), Verifiabl::Issuer.build_scan_url(**parts), vector.fetch("id")
      assert_equal vector.fetch("sandboxScanUrl"), Verifiabl::Issuer.build_scan_url(**parts, environment: :sandbox), vector.fetch("id")
    end
  end

  def test_rejects_every_shared_malformed_payload_case
    vectors.fetch("invalidPayloads").each do |vector|
      parts = {
        verifiabl_reference: vector.fetch("reference"),
        encrypted_pii: ciphertext(vector.fetch("ciphertext"))
      }
      vector.fetch("operations").each do |operation|
        error = assert_raises(ArgumentError, "#{vector.fetch("id")}:#{operation}") do
          if operation == "payload"
            Verifiabl::Issuer.build_barcode_payload(**parts)
          else
            Verifiabl::Issuer.build_scan_url(**parts, scan_base_url: vector["scanBaseUrl"])
          end
        end
        expected_message = {
          "invalid-reference" => "reference",
          "invalid-ciphertext" => "ciphertext",
          "insecure-scan-base-url" => "https"
        }.fetch(vector.fetch("expectedError"))
        assert_includes error.message.downcase, expected_message
      end
    end
  end

  private

  def vectors
    @vectors ||= JSON.parse(File.read(FIXTURE))
  end

  def decode_hex(value)
    [value].pack("H*").b
  end

  def ciphertext(input)
    return decode_hex(input.fetch("hex")) if input.key?("hex")

    decode_hex(input.fetch("repeatByteHex")) * input.fetch("length")
  end

  def snake_case_fields(fields)
    fields.to_h do |name, value|
      [name.gsub(/([a-z0-9])([A-Z])/, "\\1_\\2").downcase.to_sym, value]
    end
  end
end
