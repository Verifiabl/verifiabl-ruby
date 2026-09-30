# frozen_string_literal: true

require "json"
require_relative "test_helper"

class V2WireVectorsTest < Minitest::Test
  VECTORS = JSON.parse(File.read(File.expand_path("fixtures/v2-wire-vectors-v1.json", __dir__)))
  INPUTS = {
    "au-codes-and-earnings" => {
      period_start: "2026-08-01", period_end: "2026-08-31", payment_date: "2026-09-04",
      currency: "AUD", gross: "9000.00", paygw: "2250.00", net: "6750.00",
      pay_frequency: "monthly", employment_basis: "full_time",
      earnings: [
        {type: "ordinary", amount: "8987.50"},
        {type: "allowance", amount: "12.50", allowance_type: "other", other_category: "home_office"}
      ]
    },
    "nz-leave-and-dates" => {
      period_end: "2026-08-31", payment_date: "2026-09-04", currency: "NZD",
      gross: "7600.00", paye: "1710.00", net: "5890.00",
      earnings: [
        {type: "paid_leave", leave_type: "annual_holiday", amount: "7000.00"},
        {type: "overtime", amount: "600.00", units: "10.0", rate: "60.00"}
      ],
      leave_balances: {annual: {amount: "76.50", unit: "hours"}}
    }
  }.freeze

  def test_every_canonical_case_uses_native_ruby_input
    assert_equal "verifiabl-v2-wire-vectors-v1", VECTORS.fetch("format")
    assert_equal INPUTS.keys.sort, VECTORS.fetch("cases").map { |entry| entry.fetch("id") }.sort
  end

  def test_dates_codes_earnings_and_decimal_scale_on_the_wire
    VECTORS.fetch("cases").each do |entry|
      wire = Verifiabl::Issuer::Serialization.registration_to_wire(
        schema: entry.fetch("schema"), issued_at: "2026-09-04T00:00:00Z",
        payslip_non_pii: INPUTS.fetch(entry.fetch("id")),
        encryption_metadata: {iv: "\0".b * 12, tag: "\0".b * 16}
      )
      assert_equal entry.fetch("payslip_non_pii"), wire.fetch("payslip_non_pii"), entry.fetch("id")
    end
  end
end
