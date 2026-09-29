# frozen_string_literal: true

require "verifiabl/issuer"

# Example: client is an authenticated Verifiabl::Issuer::Client; key is a
# 32-byte secret loaded from a secrets manager, never from source control.
def issue_prepared_v2(client, key)
  issued_at = Time.now.utc
  au = Verifiabl::Issuer.prepare_australian_v2_payslip(
    pii: {employee_name: "Example Employee", employer_name: "Example Pty Ltd"},
    payslip_non_pii: {period_end: "2026-08-31", payment_date: "2026-09-04", currency: "AUD",
                      gross: "9000.00", paygw: "2250.00", net: "6750.00"},
    issued_at:, key:
  )
  # Atomically persist au.registration and
  # au.barcode_parts(au.verifiabl_reference).fetch(:encrypted_pii) before sending.
  # On restart, resend the same registration and render with the saved ciphertext.
  result = client.register_non_pii(**au.registration)
  barcode = Verifiabl::Issuer.build_barcode_svg(**au.barcode_parts(result.verifiabl_reference), environment: :sandbox)

  nz = Verifiabl::Issuer.prepare_new_zealand_v2_payslip(
    pii: {employee_name: "Example Employee", employer_name: "Example NZ Ltd"},
    payslip_non_pii: {period_end: "2026-08-31", payment_date: "2026-09-04", currency: "NZD",
                      gross: "7600.00", paye: "1710.00", net: "5890.00"},
    issued_at:, key:
  )
  # The API-managed endpoint generates its own reference; do not replay an
  # ambiguous failure as though nz.verifiabl_reference were its idempotency key.
  api_managed = client.register_and_build_barcode(**nz.api_managed_registration)
  # For batches: client.register_non_pii_batch([au.registration.merge(external_id: "PAY-1")])
  # Pair each batch result with its own prepared.barcode_parts(result.verifiabl_reference).
  [barcode, api_managed]
end
