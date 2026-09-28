# frozen_string_literal: true

require "bigdecimal"
require_relative "test_helper"

class ValidationTest < Minitest::Test
  VALID = {
    schema: "au.payslip.v1",
    issued_at: "2026-06-11T00:00:00Z",
    payslip_non_pii: {period_start: "2026-06-01", period_end: "2026-06-15"},
    encryption_metadata: {iv: "\0".b * 12, tag: "\0".b * 16}
  }.freeze

  def test_passes_future_schema_identifiers_through_to_the_api
    wire = Verifiabl::Issuer::Serialization.registration_to_wire(**VALID.merge(schema: "au.payslip.v3"))
    assert_equal "au.payslip.v3", wire.fetch("schema")

    batch = Verifiabl::Issuer::Serialization.prepare_batch(
      records: [VALID.merge(schema: "au.payslip.v3", verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv")]
    )
    assert_equal "au.payslip.v3", batch.first.fetch("records").first.fetch("schema")
    assert_equal [0], batch[1]
    assert_empty batch[2]
  end

  def test_v2_rejects_unknown_fields_at_every_depth
    %w[au.payslip.v2 nz.payslip.v2].each do |schema|
      [{"employee_name" => "Jane"}, {"hourly" => {"hours" => "76", "employee_name" => "Jane"}},
        {"deductions" => [{"account_name" => "Jane"}]}].each do |payslip|
        assert_raises(ArgumentError) { Verifiabl::Issuer::NonPiiV2.validate!(schema, payslip) }
      end
      Verifiabl::Issuer::NonPiiV2.validate!(schema, {"gross" => "100", "payment_date" => "not a date"})
    end
  end

  def test_v2_rejects_containers_at_scalar_leaves_but_defers_scalar_values
    %w[au.payslip.v2 nz.payslip.v2].each do |schema|
      [{payment_date: {employee_name: "Jane"}},
        {payment_date: [{employee_name: "Jane"}]}].each do |payslip|
        error = assert_raises(ArgumentError) do
          Verifiabl::Issuer::Serialization.registration_to_wire(
            **VALID.merge(schema:, payslip_non_pii: v2_payload(schema, payslip))
          )
        end
        assert_match(/must be a scalar/, error.message)
        refute_includes error.message, "Jane"
      end

      wire = Verifiabl::Issuer::Serialization.registration_to_wire(
        **VALID.merge(schema:, payslip_non_pii: v2_payload(schema, payment_date: "not a date"))
      )
      assert_equal "not a date", wire.dig("payslip_non_pii", "payment_date")
    end
  end

  def test_v2_numbers_must_be_plain_decimal_strings_before_transport
    %w[au.payslip.v2 nz.payslip.v2].each do |schema|
      ["", "1e3", "+1", "1,234.56", "$1.00", "(1.00)", "1.", ".5", "1.5\n", "\n1.5", "١", 1234, 12.5,
        BigDecimal("1.5"), nil, {value: "1.50"}, {employee_name: "Jane"}, ["1"]].each do |gross|
        error = assert_raises(ArgumentError, "#{schema} #{gross.inspect}") do
          Verifiabl::Issuer::Serialization.registration_to_wire(
            **VALID.merge(schema:, payslip_non_pii: v2_payload(schema, gross:))
          )
        end
        assert_equal "payslip_non_pii.gross must be a plain decimal String, for example \"1234.56\"", error.message
      end

      error = assert_raises(ArgumentError) do
        Verifiabl::Issuer::Serialization.registration_to_wire(
          **VALID.merge(schema:, payslip_non_pii: v2_payload(schema, earnings: [{type: "ordinary", amount: "SECRET"}]))
        )
      end
      assert_equal "payslip_non_pii.earnings[0].amount must be a plain decimal String, for example \"1234.56\"", error.message
    end
  end

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

  def v2_payload(schema, extras = {})
    {:period_end => "2026-06-15", :payment_date => "2026-06-15", :currency => "AUD",
     :gross => "100", :net => "80",
     ((schema == "au.payslip.v2") ? :paygw : :paye) => "20"}.merge(extras)
  end

  def test_period_start_is_optional_only_for_v2_schemas
    assert_raises(ArgumentError) do
      Verifiabl::Issuer::Serialization.registration_to_wire(
        **VALID.merge(payslip_non_pii: {period_end: "2026-06-15"})
      )
    end

    %w[au.payslip.v2 nz.payslip.v2].each do |schema|
      wire = Verifiabl::Issuer::Serialization.registration_to_wire(
        **VALID.merge(schema:, payslip_non_pii: v2_payload(schema))
      )
      refute wire.fetch("payslip_non_pii").key?("period_start")
    end
  end

  def test_sends_v2_decimal_strings_exactly_as_given
    ["1.50", "1.5", "-0.00", "47.3684", "-76", "0.10000000000000000000000000000001"].each do |gross|
      wire = Verifiabl::Issuer::Serialization.registration_to_wire(
        **VALID.merge(
          schema: Verifiabl::Issuer::AUSTRALIAN_PAYSLIP_V2_SCHEMA,
          payslip_non_pii: v2_payload("au.payslip.v2", gross:, hourly: {ordinary_rate: "47.3684", hours: "-1.5", amount: gross})
        )
      )

      assert_equal gross, wire.dig("payslip_non_pii", "gross")
      assert_equal({"ordinary_rate" => "47.3684", "hours" => "-1.5", "amount" => gross}, wire.dig("payslip_non_pii", "hourly"))
    end
  end

  def test_requires_a_supported_v2_currency_before_transport
    %w[au.payslip.v2 nz.payslip.v2].each do |schema|
      ["XYZ", "aud", "", nil, :AUD, "XTS", "XXX", "XAU", "CLF"].each do |currency|
        error = assert_raises(ArgumentError, "#{schema} #{currency.inspect}") do
          Verifiabl::Issuer::Serialization.registration_to_wire(
            **VALID.merge(schema:, payslip_non_pii: v2_payload(schema, currency:))
          )
        end
        assert_equal "currency is required and must be a supported ISO 4217 currency code, for example AUD", error.message
      end

      assert_raises(ArgumentError) do
        Verifiabl::Issuer::Serialization.registration_to_wire(
          **VALID.merge(schema:, payslip_non_pii: v2_payload(schema).except(:currency))
        )
      end

      %w[NZD JPY XAF XOF XCD XPF ZWG].each do |currency|
        wire = Verifiabl::Issuer::Serialization.registration_to_wire(
          **VALID.merge(schema:, payslip_non_pii: v2_payload(schema, currency:))
        )
        assert_equal currency, wire.dig("payslip_non_pii", "currency")
      end
    end
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
