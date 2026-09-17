# frozen_string_literal: true

# snippet:start:ruby.basic-issuance
require "base64"
require "fileutils"
require "verifiabl/issuer"

PAYSLIP = {
  external_id: "PAY-1001",
  pii: {
    employee_name: "Jane A. Doe",
    position: "Senior Developer",
    department: "Engineering",
    employer_abn: "12345678901",
    bsb: "062-000",
    account_number: "12345678",
    account_name: "Jane A Doe",
    address: "12 Example St, Sydney NSW 2000"
  },
  non_pii: {
    period_start: "2026-08-01",
    period_end: "2026-08-31",
    payment_date: "2026-09-04",
    currency: "AUD",
    gross_cents: 900_000,
    paygw_cents: 225_000,
    net_cents: 675_000,
    ytd_gross_cents: 5_400_000,
    ytd_paygw_cents: 1_350_000
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
plaintext = Verifiabl::Issuer.format_pii(PAYSLIP.fetch(:pii))

encrypted = Verifiabl::Issuer.encrypt_pii(plaintext, provider_encryption_key)

registration = {
  schema: "au.payslip.v1",
  issued_at: Time.now.utc,
  payslip_non_pii: PAYSLIP.fetch(:non_pii),
  encryption_metadata: encrypted.encryption_metadata
}

result = issuer.register_non_pii(**registration)

barcode = Verifiabl::Issuer.build_barcode_svg(
  verifiabl_reference: result.verifiabl_reference,
  encrypted_pii: encrypted.encrypted_pii,
  environment: :sandbox
)

output_path = File.expand_path("output/self-managed-barcode.svg", __dir__)
FileUtils.mkdir_p(File.dirname(output_path))

File.write(output_path, barcode.svg)
puts "Registered #{result.verifiabl_reference} and wrote #{output_path}"
# snippet:end:ruby.basic-issuance
