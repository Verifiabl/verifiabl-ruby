# frozen_string_literal: true

# snippet:start:ruby.api-managed-issuance
require "base64"
require "fileutils"
require "verifiabl/issuer"

PAYSLIP = {
  external_id: "PAY-1002",
  pii: {
    employee_name: "Zoë Nguyễn",
    ird_number: "***-***-***",
    position: "Product Designer",
    department: "Product",
    employer_name: "Example Payroll NZ Ltd",
    account_number: "**-****-*******-**",
    account_name: "Zoë Nguyễn",
    address: {lines: ["44 Harbour Rd"], suburb: "Parnell", city: "Auckland", postcode: "1052"}
  },
  non_pii: {
    period_end: "2026-08-31",
    payment_date: "2026-09-04",
    currency: "NZD",
    gross: "7600.00",
    paye: "1710.00",
    net: "5890.00"
  }
}.freeze

issuer = Verifiabl::Issuer::Client.new(
  Verifiabl::Issuer::Configuration.new(
    environment: :sandbox,
    client_id: ENV.fetch("VERIFIABL_CLIENT_ID"),
    client_secret: ENV.fetch("VERIFIABL_CLIENT_SECRET")
  )
)

provider_encryption_key = Base64.strict_decode64(
  ENV.fetch("VERIFIABL_ENCRYPTION_KEY_BASE64")
)
prepared = Verifiabl::Issuer.prepare_new_zealand_v2_payslip(
  pii: PAYSLIP.fetch(:pii),
  payslip_non_pii: PAYSLIP.fetch(:non_pii),
  issued_at: Time.now.utc,
  key: provider_encryption_key
)
# API-managed registration allocates its own reference. Do not replay an
# ambiguous failure as if prepared.verifiabl_reference were its idempotency key.
result = issuer.register_and_build_barcode(**prepared.api_managed_registration)

output_path = File.expand_path("output/api-managed-barcode.png", __dir__)
FileUtils.mkdir_p(File.dirname(output_path))

File.binwrite(output_path, Base64.strict_decode64(result.barcode.data))
puts "Registered #{result.verifiabl_reference} and wrote #{output_path}"
# snippet:end:ruby.api-managed-issuance
