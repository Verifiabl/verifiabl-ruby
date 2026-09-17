# Verifiabl Ruby SDK

Official Ruby SDK for issuing Verifiabl payslip QR codes. It includes offline protocol primitives,
cross-SDK-compatible QR generation, deterministic SVG/PNG rendering, a hardened OAuth issuer
client, RBS signatures, and packed-gem consumer qualification.

## Installation

The current release is a release candidate. Add its exact version to your bundle:

```ruby
gem "verifiabl-issuer", "0.1.0-rc.1"
```

Then run `bundle install`. Keep the exact version until a stable release is available.

Bundler loads the gem through its package-name entry point:

```ruby
require "verifiabl-issuer"
```

That entry point is a compatibility shim and loads the canonical namespaced entry point. Applications
that require dependencies explicitly can use this path instead:

```ruby
require "verifiabl/issuer"
```

Both forms load the same `Verifiabl::Issuer` implementation; applications do not need to require
both. Ruby 3.3 or newer is required. QR encoding uses the pure-Ruby `rqrcode_core` gem; Verifiabl
owns canonical mask selection and badge rendering rather than depending on the gem's PNG or SVG
exporters.

## Configuration

Construct and retain an issuer client explicitly:

```ruby
issuer = Verifiabl::Issuer::Client.new(
  Verifiabl::Issuer::Configuration.new(
    environment: :sandbox,
    client_id: ENV.fetch("VERIFIABL_CLIENT_ID"),
    client_secret: ENV.fetch("VERIFIABL_CLIENT_SECRET")
  )
)
```

The SDK is framework-neutral: it does not load Rails or Active Support, install framework hooks, or
configure logging. Applications own their long-lived client and place it in their normal dependency
container; Rails applications commonly construct it in an initializer. A client is safe to share
between threads and refreshes its OAuth cache after a process fork.

Set `on_request`, `on_response`, and `on_error` on `Configuration` when request telemetry is needed.
Events contain request metadata but never request bodies, credentials, or payslip data. Observer
failures do not change request behavior.

The default overall deadline is 30 seconds and includes OAuth, 401 refresh, retry attempts, and
backoff. The Verifiabl reference is the idempotency key. `register_non_pii` generates and sends one
when omitted, so it and batch registration can safely retry transport failures, 408s, 429s, and 5xx
responses. API-managed barcode registration uses a server-generated reference and retries only 429,
which is rejected before processing. Configure these limits when needed:

```ruby
configuration = Verifiabl::Issuer::Configuration.new(
  client_id: ENV.fetch("VERIFIABL_CLIENT_ID"),
  client_secret: ENV.fetch("VERIFIABL_CLIENT_SECRET"),
  timeout: 10,
  max_retries: 2
)
issuer = Verifiabl::Issuer::Client.new(configuration)
```

Endpoint overrides are intended only for development. Issuer overrides require HTTPS except for
loopback HTTP. OAuth overrides are restricted to Verifiabl auth hosts or loopback addresses.

## Issue payslips

Choose one barcode flow for each payslip. Do not call both registration methods for the same
issuance.

### Self-managed barcode flow

Use this flow when your application renders the barcode. The following example is generated from
the runnable
[`examples/issuer/basic/issue_payslips_self_managed.rb`](../../examples/issuer/basic/issue_payslips_self_managed.rb)
source.

<!-- snippet:ruby.basic-issuance:start -->

```ruby
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
```

<!-- snippet:ruby.basic-issuance:end -->

`register_non_pii` sends the non-PII fields and encryption metadata, but not the encrypted PII. The
application combines the returned reference with the encrypted PII to render the SVG locally.

### API-managed barcode flow

Use this alternative when Verifiabl should render the barcode PNG. The following example is
generated from the runnable
[`examples/issuer/basic/issue_payslips_api_managed.rb`](../../examples/issuer/basic/issue_payslips_api_managed.rb)
source.

<!-- snippet:ruby.api-managed-issuance:start -->

```ruby
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

result = issuer.register_and_build_barcode(
  encrypted_pii: encrypted.encrypted_pii,
  **registration
)

output_path = File.expand_path("output/api-managed-barcode.png", __dir__)
FileUtils.mkdir_p(File.dirname(output_path))

File.binwrite(output_path, Base64.strict_decode64(result.barcode.data))
puts "Registered #{result.verifiabl_reference} and wrote #{output_path}"
```

<!-- snippet:ruby.api-managed-issuance:end -->

`register_and_build_barcode` sends the encrypted PII in addition to the non-PII fields and encryption
metadata. Verifiabl uses the ciphertext to render the returned PNG and does not retain it. Plaintext
PII is never sent in either flow.

### Retries and batches

For a self-managed registration that must remain retryable across process restarts, generate and
persist the reference before the first call, then reuse it on every attempt:

```ruby
reference = Verifiabl::Issuer.generate_verifiabl_reference
persist_with_issuance_record(reference)
result = issuer.register_non_pii(
  verifiabl_reference: reference,
  **registration
)
```

For pay runs, register up to 1,000 self-managed records in one request:

```ruby
batch = issuer.register_non_pii_batch(records)
batch.results.each do |item|
  case item.status
  when "created", "duplicate"
    puts item.verifiabl_reference
  when "error"
    warn "#{item.external_id}: #{item.code} #{item.detail}"
  end
end
```

The API returns `201` for the first registration and `200` for an identical replay. Reusing a
reference with different content raises `ApiError` with code `CONFLICT`.

Successful calls return immutable typed result objects under `Verifiabl::Issuer::Responses`.
Malformed successful API responses raise `TransportError`. Issuer HTTP errors raise `ApiError` (or
`IvReuseError` for `IV_REUSED`). Non-timeout OAuth connectivity failures and invalid or unsuccessful
token responses raise `AuthError`. Deadline expiry raises `TimeoutError`, while issuer network
failures raise `TransportError`. Request and error messages never include the submitted payslip body.

## Offline protocol primitives

Format and encrypt PII locally. The plaintext must never be logged or sent to Verifiabl:

```ruby
plaintext = Verifiabl::Issuer.format_pii(
  employee_name: "Jane Doe",
  employer_abn: "53004085616",
  address: "12 Example St, Sydney NSW 2000"
)

encrypted = Verifiabl::Issuer.encrypt_pii(plaintext, provider_encryption_key)
reference = Verifiabl::Issuer.generate_verifiabl_reference

scan_url = Verifiabl::Issuer.build_scan_url(
  verifiabl_reference: reference,
  encrypted_pii: encrypted.encrypted_pii,
  environment: :sandbox
)

xmp_payload = Verifiabl::Issuer.build_barcode_payload(
  verifiabl_reference: reference,
  encrypted_pii: encrypted.encrypted_pii
)

svg = Verifiabl::Issuer.build_barcode_svg(
  verifiabl_reference: reference,
  encrypted_pii: encrypted.encrypted_pii,
  environment: :sandbox,
  width: 480
)
File.write("barcode.svg", svg.svg)

png = Verifiabl::Issuer.build_barcode_png(
  verifiabl_reference: reference,
  encrypted_pii: encrypted.encrypted_pii,
  environment: :sandbox,
  width: 720
)
File.binwrite("barcode.png", png.png)
```

The renderers use the same official vector frame, rounded finder geometry, and QR error-correction
ladder as the Node and .NET SDKs. SVG widths are continuously scalable from 480 upward. PNG frames
are pre-rasterised for deterministic cross-SDK output and therefore support only `480`, `720`,
`960`, and `1440` pixels. Use `max_error_correction: :q` for greater damage recovery; the default is
`:m`, and the renderer steps down only when necessary to preserve the three-pixel module floor.
Each result's `degraded` field (`svg.degraded` or `png.degraded` above) is true when the renderer
steps down from the requested ceiling or the modules fall below the ideal four-pixel size.

`provider_encryption_key` must be exactly 32 bytes and loaded from a KMS or secrets manager. Every
encryption call creates a fresh AES-256-GCM IV. Ciphertext, IV, and authentication tags are exposed
as binary Ruby strings (`Encoding::BINARY`) and can be persisted directly in binary database
columns. The SDK encodes them only at an external boundary: base64url for issuer API requests and
uppercase, unpadded RFC 4648 Base32 for v2 barcode and XMP output. PDF integrations should store `xmp_payload` under
XMP namespace `https://verifiabl.io/ns/`, property `payload`. QR v2 is encoded as an explicit byte
prefix and alphanumeric ciphertext segment. Matrix version, mask, and modules match the Node and
.NET SDKs.

## Development

```sh
bundle install
bundle exec rake
(cd gems/verifiabl-issuer && bundle exec gem build verifiabl-issuer.gemspec)
bundle exec ruby script/packed_gem_check.rb
```

## License

[MIT](./LICENSE)
