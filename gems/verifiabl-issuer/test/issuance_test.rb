# frozen_string_literal: true

require_relative "test_helper"

class IssuanceTest < Minitest::Test
  KEY = "k".b * 32
  ISSUED_AT = Time.utc(2026, 9, 4)
  AU = {period_end: "2026-08-31", currency: "AUD", gross: "9000.00", paygw: "2250.00", net: "6750.00"}.freeze
  NZ = {period_end: "2026-08-31", currency: "NZD", gross: "7600.00", paye: "1710.00", net: "5890.00"}.freeze

  def test_both_jurisdictions_produce_self_and_api_managed_requests
    [[:prepare_australian_v2_payslip, {employer_name: "Private AU"}, AU, "au.payslip.v2"],
      [:prepare_new_zealand_v2_payslip, {employee_name: "Private NZ"}, NZ, "nz.payslip.v2"]].each do |method, pii, payslip, schema|
      prepared = Verifiabl::Issuer.public_send(method, pii:, payslip_non_pii: payslip, issued_at: ISSUED_AT, key: KEY)
      assert_equal schema, prepared.registration.fetch(:schema)
      assert_equal prepared.verifiabl_reference, prepared.registration.fetch(:verifiabl_reference)
      refute prepared.api_managed_registration.key?(:verifiabl_reference)
      assert_equal prepared.barcode_parts(prepared.verifiabl_reference).fetch(:encrypted_pii), prepared.api_managed_registration.fetch(:encrypted_pii)
      assert_equal schema, Verifiabl::Issuer::Serialization.registration_to_wire(**prepared.registration.except(:verifiabl_reference)).fetch("schema")
      assert_equal schema, Verifiabl::Issuer::Serialization.register_and_build_barcode_to_wire(**prepared.api_managed_registration).fetch("schema")
      wire = Verifiabl::Issuer::Serialization.batch_to_wire(records: [prepared.registration.merge(external_id: "PAY-1")])
      assert_equal schema, wire.fetch("records").first.fetch("schema")
    end
  end

  def test_mixed_jurisdiction_fails_before_encryption_without_pii_in_error
    error = assert_raises(ArgumentError) do
      Verifiabl::Issuer.prepare_australian_v2_payslip(pii: {employee_name: "Private Person"}, payslip_non_pii: NZ, issued_at: ISSUED_AT, key: "bad")
    end
    assert_match(/paye/, error.message)
    refute_match(/Private Person/, error.message)
  end

  def test_reference_is_fixed_for_retries
    reference = Verifiabl::Issuer.generate_verifiabl_reference
    prepared = Verifiabl::Issuer.prepare_australian_v2_payslip(pii: {}, payslip_non_pii: AU, issued_at: ISSUED_AT, key: KEY, verifiabl_reference: reference)
    assert_equal reference, prepared.registration.fetch(:verifiabl_reference)
    assert_equal prepared.registration, prepared.registration
    refute prepared.api_managed_registration.key?(:verifiabl_reference)
  end

  def test_prepared_values_are_independent_of_mutable_inputs_and_results
    reference = Verifiabl::Issuer.generate_verifiabl_reference
    earnings = [{type: "ordinary", amount: "100.50"}]
    payslip = AU.merge(ytd: {taxable: "9000.00".dup}, earnings:)
    prepared = Verifiabl::Issuer.prepare_australian_v2_payslip(pii: {}, payslip_non_pii: payslip, issued_at: ISSUED_AT, key: KEY, verifiabl_reference: reference)
    original_registration = Verifiabl::Issuer::Serialization.registration_to_wire(**prepared.registration.except(:verifiabl_reference))
    original_ciphertext = prepared.barcode_parts(prepared.verifiabl_reference).fetch(:encrypted_pii)
    registration = prepared.registration
    api_managed = prepared.api_managed_registration
    parts = prepared.barcode_parts(prepared.verifiabl_reference)

    reference.replace("A" * 22)
    payslip.fetch(:ytd).fetch(:taxable).replace("1.00")
    earnings.clear
    registration.fetch(:payslip_non_pii).fetch(:ytd).fetch(:taxable).replace("2.00")
    registration.fetch(:payslip_non_pii).fetch(:earnings).clear
    registration.fetch(:encryption_metadata).fetch(:iv).replace("bad")
    registration.fetch(:verifiabl_reference).replace("B" * 22)
    api_managed[:schema] = "nz.payslip.v2"
    api_managed.fetch(:payslip_non_pii).fetch(:ytd).fetch(:taxable).replace("3.00")
    api_managed.fetch(:encryption_metadata).fetch(:tag).replace("bad")
    api_managed.fetch(:encrypted_pii).replace("bad")
    parts.fetch(:verifiabl_reference).replace("C" * 22)
    parts.fetch(:encrypted_pii).replace("bad")

    assert_raises(FrozenError) { prepared.verifiabl_reference.replace("D" * 22) }
    assert_equal prepared.verifiabl_reference, prepared.registration.fetch(:verifiabl_reference)
    assert_equal original_registration, Verifiabl::Issuer::Serialization.registration_to_wire(**prepared.registration.except(:verifiabl_reference))
    assert_equal original_ciphertext, prepared.api_managed_registration.fetch(:encrypted_pii)
    assert_equal original_ciphertext, prepared.barcode_parts(prepared.verifiabl_reference).fetch(:encrypted_pii)
    refute prepared.api_managed_registration.key?(:verifiabl_reference)
  end
end
