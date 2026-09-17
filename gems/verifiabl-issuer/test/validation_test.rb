# frozen_string_literal: true

require_relative "test_helper"

class ValidationTest < Minitest::Test
  VALID = {
    schema: "au.payslip.v1",
    issued_at: "2026-06-11T00:00:00Z",
    payslip_non_pii: {period_start: "2026-06-01", period_end: "2026-06-15"},
    encryption_metadata: {iv: "\0".b * 12, tag: "\0".b * 16}
  }.freeze

  def test_rejects_invalid_registration_fields_before_transport
    invalid = [
      [:schema, "AU"],
      [:issued_at, "yesterday"],
      [:payslip_non_pii, {period_start: "2026-02-30"}],
      [:encryption_metadata, {iv: "short", tag: "\0".b * 16}],
      [:encryption_metadata, {iv: "A" * 12, tag: "\0".b * 16}],
      [:encryption_metadata, {iv: 12, tag: "\0".b * 16}],
      [:encryption_metadata, {iv: "\0".b * 12, tag: []}]
    ]

    invalid.each do |field, value|
      assert_raises(ArgumentError, field.to_s) do
        Verifiabl::Issuer::Serialization.registration_to_wire(**VALID.merge(field => value))
      end
    end
  end

  def test_rejects_symbol_and_string_key_collisions
    registration = VALID.merge(
      payslip_non_pii: {period_start: "2026-06-01"}.merge("period_start" => "not-a-date"),
      encryption_metadata: {iv: "\0".b * 12, tag: "\0".b * 16}.merge("iv" => "invalid")
    )

    error = assert_raises(ArgumentError) do
      Verifiabl::Issuer::Serialization.registration_to_wire(**registration)
    end
    assert_match("duplicate key after string normalization", error.message)
  end

  def test_serializes_time_at_utc_millisecond_precision
    wire = Verifiabl::Issuer::Serialization.registration_to_wire(
      **VALID.merge(issued_at: Time.new(2026, 6, 11, 10, 30, 0.1234, "+10:00"))
    )

    assert_equal "2026-06-11T00:30:00.123Z", wire.fetch("issued_at")
  end

  def test_validates_every_batch_reference_and_external_id
    record = VALID.merge(verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv", external_id: "payroll-123")
    wire = Verifiabl::Issuer::Serialization.batch_to_wire(records: [record])
    assert_equal "payroll-123", wire.fetch("records").first.fetch("external_id")

    assert_raises(ArgumentError) do
      Verifiabl::Issuer::Serialization.batch_to_wire(records: [record.merge(verifiabl_reference: "bad")])
    end
    assert_raises(ArgumentError) do
      Verifiabl::Issuer::Serialization.batch_to_wire(records: [record.merge(external_id: "line\nbreak")])
    end
  end

  def test_rejects_invalid_binary_ciphertext
    ["".b, "text", nil, [], "x".b * 7_501].each do |value|
      assert_raises(ArgumentError) do
        Verifiabl::Issuer::Serialization.register_and_build_barcode_to_wire(encrypted_pii: value, **VALID)
      end
    end
  end

  def test_base64url_encodes_binary_ciphertext_at_the_wire_boundary
    wire = Verifiabl::Issuer::Serialization.register_and_build_barcode_to_wire(
      encrypted_pii: "foobar".b,
      **VALID
    )

    assert_equal "Zm9vYmFy", wire.fetch("encrypted_pii")
  end
end
