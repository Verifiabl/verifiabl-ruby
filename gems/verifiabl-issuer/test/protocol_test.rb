# frozen_string_literal: true

require "json"
require "openssl"
require_relative "test_helper"

class ProtocolTest < Minitest::Test
  REFERENCE = "AbCdEfGhIjKlMnOpQrStUv"
  CIPHERTEXT = "foobarbazqux".b

  def test_formats_p2_in_permanent_field_order
    assert_equal(
      "P2|Zoë Nguyễn|Ingénieure|R&D|53004085616|062-000|12345678|Zoë Nguyễn|",
      Verifiabl::Issuer.format_pii(
        employee_name: "Zoë Nguyễn",
        position: "Ingénieure",
        department: "R&D",
        employer_abn: "53004085616",
        bsb: "062-000",
        account_number: "12345678",
        account_name: "Zoë Nguyễn"
      )
    )
  end

  def test_omitted_p2_fields_are_empty_segments
    assert_equal "P2|Jane||||062-000|||", Verifiabl::Issuer.format_pii(employee_name: "Jane", bsb: "062-000")
  end

  def test_omitted_p2_fields_ignore_hash_defaults
    fields = Hash.new("unknown")
    fields[:employee_name] = "Jane"
    assert_equal "P2|Jane|||||||", Verifiabl::Issuer.format_pii(fields)

    fields = Hash.new { raise "default proc must not be called" }
    fields["employee_name"] = "Jane"
    assert_equal "P2|Jane|||||||", Verifiabl::Issuer.format_pii(fields)
  end

  def test_matches_every_canonical_p2_text_vector
    vectors.fetch("validText").each do |vector|
      assert_includes Verifiabl::Issuer.format_pii(employee_name: vector.fetch("value")), vector.fetch("value")
    end

    vectors.fetch("invalidText").each do |vector|
      value = vector.fetch("codePoints").map { |point| point.to_i(16) }.pack("U*")
      error = assert_raises(Verifiabl::Issuer::Pii::ValidationError) do
        Verifiabl::Issuer.format_pii(employee_name: value)
      end
      expected = (vector.fetch("reason") == "line-separator") ? :control_character : vector.fetch("reason").tr("-", "_").to_sym
      assert_equal [Verifiabl::Issuer::Pii::Violation.new(field: :employee_name, reason: expected)], error.violations
      refute_includes error.message, value
    end
  end

  def test_matches_the_canonical_p2_profile
    assert_equal profile.fetch("profileId"), Verifiabl::Issuer::Pii::PROFILE_ID
    assert_equal profile.fetch("unicodeVersion"), Verifiabl::Issuer::Pii::PROFILE_UNICODE_VERSION
    assert_equal profile.fetch("writerPayloadMaxUtf8Bytes"), Verifiabl::Issuer::Pii::PAYLOAD_MAX_BYTES
  end

  def test_rejects_canonical_invalid_utf8_vectors
    vectors.fetch("invalidUtf8").each do |vector|
      bytes = [vector.fetch("bytesHex")].pack("H*")
      error = assert_raises(Verifiabl::Issuer::Pii::ValidationError) do
        Verifiabl::Issuer.format_pii(employee_name: bytes)
      end
      assert_equal :invalid_unicode, error.violations.first.reason
    end
  end

  def test_rejects_canonical_unpaired_utf16_surrogates
    vectors.fetch("invalidUtf16").each do |vector|
      text = vector.fetch("codeUnits").pack("n*").force_encoding(Encoding::UTF_16BE)
      error = assert_raises(Verifiabl::Issuer::Pii::ValidationError) do
        Verifiabl::Issuer.format_pii(employee_name: text)
      end
      assert_equal :invalid_unicode, error.violations.first.reason
    end
  end

  def test_enforces_complete_p2_utf8_byte_limit
    assert_equal 1024, Verifiabl::Issuer.format_pii(employee_name: "a" * 1014).bytesize
    assert_raises(RangeError) { Verifiabl::Issuer.format_pii(employee_name: "a" * 1015) }
  end

  def test_aes_256_gcm_round_trip_matches_verifier_shape
    key = (0...32).to_a.pack("C*")
    plaintext = Verifiabl::Issuer.format_pii(employee_name: "給与明細")
    encrypted = Verifiabl::Issuer.encrypt_pii(plaintext, key)
    metadata = encrypted.encryption_metadata

    decipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
    decipher.key = key
    decipher.iv = metadata.fetch(:iv)
    decipher.auth_tag = metadata.fetch(:tag)
    decrypted = decipher.update(encrypted.encrypted_pii) + decipher.final

    assert_equal plaintext, decrypted.force_encoding(Encoding::UTF_8)
    assert_equal plaintext.bytesize, encrypted.encrypted_pii.bytesize
    assert_equal 12, metadata.fetch(:iv).bytesize
    assert_equal 16, metadata.fetch(:tag).bytesize
    assert_equal Encoding::BINARY, encrypted.encrypted_pii.encoding
    assert_equal Encoding::BINARY, metadata.fetch(:iv).encoding
    assert_equal Encoding::BINARY, metadata.fetch(:tag).encoding
  end

  def test_aes_256_gcm_rejects_tampered_ciphertext
    key = "k" * 32
    encrypted = Verifiabl::Issuer.encrypt_pii("P2|Jane||||||||", key)
    ciphertext = encrypted.encrypted_pii.dup
    ciphertext.setbyte(0, ciphertext.getbyte(0) ^ 0x01)

    assert_raises(OpenSSL::Cipher::CipherError) do
      decrypt(ciphertext, encrypted.encryption_metadata, key)
    end
  end

  def test_aes_256_gcm_only_decrypts_with_the_issuing_provider_key
    encrypted = Verifiabl::Issuer.encrypt_pii("P2|Jane||||||||", "k" * 32)

    assert_raises(OpenSSL::Cipher::CipherError) do
      decrypt(encrypted.encrypted_pii, encrypted.encryption_metadata, "x" * 32)
    end
  end

  def test_aes_256_gcm_rejects_keys_that_are_not_32_bytes
    ["", "k" * 16, "k" * 31, "k" * 33, "k" * 64].each do |key|
      error = assert_raises(ArgumentError) do
        Verifiabl::Issuer.encrypt_pii("P2||||||||", key)
      end
      assert_includes error.message, "32 bytes"
    end
  end

  def test_aes_256_gcm_uses_fresh_ivs_and_ciphertext
    key = "k" * 32
    first = Verifiabl::Issuer.encrypt_pii("P2||||||||", key)
    second = Verifiabl::Issuer.encrypt_pii("P2||||||||", key)
    refute_equal first.encryption_metadata.fetch(:iv), second.encryption_metadata.fetch(:iv)
    refute_equal first.encrypted_pii, second.encrypted_pii
  end

  def test_base32_matches_rfc_4648_vectors
    {"f" => "MY", "fo" => "MZXQ", "foo" => "MZXW6", "foob" => "MZXW6YQ", "fooba" => "MZXW6YTB", "foobar" => "MZXW6YTBOI"}.each do |input, expected|
      assert_equal expected, Verifiabl::Issuer::Base32.encode(input)
    end
  end

  def test_builds_v2_xmp_payloads
    assert_equal "2|#{REFERENCE}|MZXW6YTBOJRGC6TROV4A", Verifiabl::Issuer.build_barcode_payload(verifiabl_reference: REFERENCE, encrypted_pii: CIPHERTEXT)
  end

  def test_builds_scan_urls_and_exact_qr_segment_boundaries
    parts = Verifiabl::Issuer::Payload.scan_url_parts(verifiabl_reference: REFERENCE, encrypted_pii: "foobar".b)
    assert_equal "https://v.verifiabl.io/v/#{REFERENCE}#2.", parts.byte_prefix
    assert_equal "MZXW6YTBOI", parts.alphanumeric_ciphertext
    assert_equal parts.byte_prefix + parts.alphanumeric_ciphertext, parts.content
  end

  def test_does_not_support_legacy_v1_payloads
    assert_raises(ArgumentError) do
      Verifiabl::Issuer.build_barcode_payload(verifiabl_reference: REFERENCE, encrypted_pii: CIPHERTEXT, format: :v1)
    end
    assert_raises(ArgumentError) do
      Verifiabl::Issuer.build_scan_url(verifiabl_reference: REFERENCE, encrypted_pii: CIPHERTEXT, format: :v1)
    end
  end

  def test_rejects_invalid_binary_ciphertext
    ["".b, "text", nil, [], "x".b * 7_501].each do |ciphertext|
      error = assert_raises(ArgumentError) do
        Verifiabl::Issuer.build_barcode_payload(verifiabl_reference: REFERENCE, encrypted_pii: ciphertext)
      end
      assert_includes error.message, "bytes"

      assert_raises(ArgumentError) do
        Verifiabl::Issuer.build_scan_url(verifiabl_reference: REFERENCE, encrypted_pii: ciphertext)
      end
    end
  end

  def test_generates_128_bit_base64url_references
    references = Array.new(1_000) { Verifiabl::Issuer.generate_verifiabl_reference }
    assert references.all? { |reference| reference.match?(/\A[A-Za-z0-9_-]{22}\z/) }
    assert_equal references.length, references.uniq.length
  end

  def test_serializes_a_representative_registration
    wire = Verifiabl::Issuer::Serialization.registration_to_wire(
      schema: "au.payslip.v1",
      issued_at: "2026-06-11T00:00:00Z",
      payslip_non_pii: {period_start: "2026-06-01", gross_cents: 120_000, ytd: {taxable_cents: 500_000}},
      encryption_metadata: {iv: "\0".b * 12, tag: "\0".b * 16}
    )

    assert_equal "2026-06-11T00:00:00Z", wire.fetch("issued_at")
    assert_equal 120_000, wire.fetch("payslip_non_pii").fetch("gross_cents")
    assert_equal 500_000, wire.fetch("payslip_non_pii").fetch("ytd").fetch("taxable_cents")
    assert_equal "AAAAAAAAAAAAAAAA", wire.fetch("encryption_metadata").fetch("iv")
    assert_equal "AAAAAAAAAAAAAAAAAAAAAA", wire.fetch("encryption_metadata").fetch("tag")
    assert JSON.generate(wire)
  end

  private

  def vectors
    @vectors ||= read_fixture("p2-pii-text-profile-v1-vectors.json")
  end

  def profile
    @profile ||= read_fixture("p2-pii-text-profile-v1.json")
  end

  def read_fixture(name)
    JSON.parse(File.read(File.join(__dir__, "fixtures", name)))
  end

  def decrypt(ciphertext, metadata, key)
    decipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
    decipher.key = key
    decipher.iv = metadata.fetch(:iv)
    decipher.auth_tag = metadata.fetch(:tag)
    decipher.update(ciphertext) + decipher.final
  end
end
