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
plaintext = Verifiabl::Issuer.format_new_zealand_pii(PAYSLIP.fetch(:pii))

encrypted = Verifiabl::Issuer.encrypt_pii(plaintext, provider_encryption_key)

registration = {
  schema: Verifiabl::Issuer::NEW_ZEALAND_PAYSLIP_V2_SCHEMA,
  issued_at: Time.now.utc,
  payslip_non_pii: PAYSLIP.fetch(:non_pii),
  encryption_metadata: encrypted.encryption_metadata
}

result = issuer.register_and_build_barcode(
  encrypted_pii: encrypted.encrypted_pii,
  **registration
)

output_path = File.expand_path("output/api-managed-barcode.png", __dir__)
FileUtils.mkdir_p(File.dirname(output_path))

File.binwrite(output_path, Base64.strict_decode64(result.barcode.data))
puts "Registered #{result.verifiabl_reference} and wrote #{output_path}"
# snippet:end:ruby.api-managed-issuance
