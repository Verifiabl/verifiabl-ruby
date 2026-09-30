# Verifiabl Ruby SDK

Official Ruby SDK for issuing Verifiabl payslip QR codes. It includes offline protocol primitives,
cross-SDK-compatible QR generation, deterministic SVG/PNG rendering, a hardened OAuth issuer
client, RBS signatures, and packed-gem consumer qualification.

## Installation

Add the stable release to your bundle:

```ruby
gem "verifiabl-issuer", "0.1.0"
```

Then run `bundle install`.

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

The default timeout budget is 30 seconds across OAuth, token-lock waits, 401 refresh, retries,
and backoff. Lock waits are bounded, and the budget is checked between operations. The built-in
Net::HTTP transport applies the remaining budget to open, read, and write timeouts, but those are
per-I/O inactivity timeouts, **not a hard wall-clock limit**: DNS or a response that keeps sending
bytes can outlast the budget. A completed request that returns after the deadline raises
`TimeoutError`; blocking custom adapters can also exceed it. The SDK does not use
`Timeout.timeout`, which can asynchronously interrupt sockets and corrupt persistent connections.

The Verifiabl reference is the idempotency key. `register_non_pii` generates and sends one
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

## Connection reuse and custom transports

The default transport opens and closes a TCP/TLS connection for each request. For high-volume
batch issuing, supply `transport:` to avoid repeated handshakes. No pooling dependency is installed
by default. For example, add `gem "net-http-persistent", "~> 4.0"` to your application's Gemfile.
Like the built-in transport, this example uses per-I/O timeouts and **does not enforce a total
wall-clock deadline**:

```ruby
require "net/http/persistent"

# Create one adapter/client per worker, after forking. This example is sequential:
# do not share it across threads because timeout settings are mutable.
http = Net::HTTP::Persistent.new(name: "verifiabl-issuer")
http.max_retries = 0 # Leave retry/idempotency decisions to the SDK.
transport = lambda do |method:, url:, headers:, body:, timeout:|
  raise ArgumentError, "unsupported method" unless method == :post

  http.open_timeout = timeout
  http.read_timeout = timeout
  http.write_timeout = timeout
  uri = URI.parse(url)
  request = Net::HTTP::Post.new(uri, headers)
  request.body = body
  response = http.request(uri, request)
  Verifiabl::Issuer::Client::Response.new(
    status: response.code.to_i,
    headers: response.each_header.to_h,
    body: response.body.to_s
  )
end
issuer = Verifiabl::Issuer::Client.new(configuration, transport: transport)
begin
  # Use issuer.register_non_pii(...) or issuer.register_non_pii_batch(...).
ensure
  http.shutdown
end
```

The adapter receives `method:`, `url:`, `headers:`, `body:` (serialized JSON), and `timeout:`
(remaining seconds), for both OAuth and issuer requests. Return an object with integer `status`,
`headers` (prefer lowercase keys), and string `body` readers. Adapters own their I/O and
pool-acquisition timeouts, failed-connection cleanup, and must not retry non-idempotent calls.
For a **strict total deadline**, bring an adapter that bounds DNS, pool waits, TLS, writes, headers,
and the complete body by the remaining `timeout:` budget (including trickling responses). The SDK
cannot forcibly interrupt arbitrary blocking adapter code. Native `Timeout::Error` subclasses
become SDK `TimeoutError`; socket/I/O failures become SDK errors. The application owns adapter
shutdown, thread safety, and post-fork recreation.

## Issue payslips

For new AU/NZ v2 integrations, prepare the payslip once with its jurisdiction-specific helper. The helper selects the schema and PII formatter, validates non-PII fields with the SDK's existing rules, and encrypts locally. Choose one barcode flow for each payslip. Do not call both registration methods for the same issuance.

### AU2 and NZ2 payslip profiles

Use `prepare_australian_v2_payslip` for Australian records or
`prepare_new_zealand_v2_payslip` for New Zealand records. Each selects the
matching v2 schema and PII formatter internally. The AU2 formatter accepts
employer name and ABN separately, then writes the ABN when present or falls
back to the name. Structured address components collapse into one address
display field.

```ruby
require "base64"

provider_encryption_key = Base64.strict_decode64(
  ENV.fetch("VERIFIABL_ENCRYPTION_KEY_BASE64")
)
prepared = Verifiabl::Issuer.prepare_australian_v2_payslip(
  pii: {
    employee_name: "Jane A. Doe",
    employer_name: "Example Payroll Pty Ltd",
    employer_abn: "12 345 678 901",
    address: {lines: ["A204/11-17 Eve Street"], suburb: "Erskineville", state_or_territory: "NSW", postcode: "2043"}
  },
  payslip_non_pii: {
    period_end: "2026-05-31", payment_date: "2026-06-04", currency: "AUD",
    gross: "8125.00", paygw: "2030.00", net: "6095.00"
  },
  issued_at: Time.now.utc,
  key: provider_encryption_key
)
# Persist the registration and ciphertext together before sending (binary columns).
saved_registration = prepared.registration
saved_ciphertext = prepared.barcode_parts(prepared.verifiabl_reference).fetch(:encrypted_pii)
# Persist saved_registration and saved_ciphertext atomically. The registration
# has the reference, IV and tag, but not the ciphertext.
registration = issuer.register_non_pii(**saved_registration)
# After a restart, resend saved_registration unchanged and render from saved_ciphertext.
barcode = Verifiabl::Issuer.build_barcode_svg(
  verifiabl_reference: registration.verifiabl_reference,
  encrypted_pii: saved_ciphertext, environment: :sandbox
)
```

For NZ, pass the `ird_number` and the printed employer and bank details in the
NZ helper's `pii:` input. NZ2 carries the printed employee IRD number,
employer name, account number and account name. It has no BSB or NZBN field.

Both formatters always write eight positions, including empty trailing fields. AU addresses render
as address lines followed by `suburb state postcode`; NZ addresses render as address lines, optional
suburb, then `city postcode`. Country is implicit. The complete UTF-8 plaintext is limited to 1024
bytes.

The preparation helpers pair the AU2/NZ2 PII format with the matching v2
non-PII schema. Their input does not accept a schema, formatted plaintext, or
ciphertext. They do not check whether input values describe a real payslip or
whether printed non-PII strings contain personal information. Keep employee
PII out of non-PII fields. Advanced integrations can still select the schema
and formatter separately with the low-level APIs. PII format and non-PII
schema versions are independent; legacy v1 verification remains supported.
The verifier currently interprets AU2 only for `au.payslip.v2` and NZ2 only
for `nz.payslip.v2`. Future non-PII schemas need an explicit verifier reader
mapping before reusing either PII format; an unknown schema falls back to raw
PII text rather than structured fields.

Every AU2 and NZ2 amount, rate and quantity is a plain decimal `String`, for example `"1234.56"`,
`"-25.00"` or `"47.3684"`: an optional leading `-`, digits, and an optional `.` followed by digits.
The SDK sends the string exactly as given, so `"1.50"` and `"1.5"` stay distinct. It rejects any
other value, including an `Integer`, `Float` or `BigDecimal`, before sending. `period_start` is
optional for AU2 and NZ2. `currency` is required and must be a current ISO 4217 currency code
(`Verifiabl::Issuer::SUPPORTED_V2_CURRENCIES`). Fund codes and codes with no minor unit, for example
`XAU` or `XXX`, are not accepted, because wages are paid in legal tender. The SDK also rejects unlisted fields (including
nested fields) before transport to avoid sending accidental PII; the API validates the remaining
payslip rules.

For common fixed AU/NZ v2 fields, use the frozen discovery lists in
`Verifiabl::Issuer::PayslipCodes`. The lists are scoped by jurisdiction and
contain the known codes, including the earnings discriminators:

```ruby
au = Verifiabl::Issuer::PayslipCodes::Australian
nz = Verifiabl::Issuer::PayslipCodes::NewZealand
au::PAY_FREQUENCIES # => ["weekly", "fortnightly", "monthly", "quarterly"]
au::OTHER_ALLOWANCE_CATEGORIES.include?("home_office") # => true
nz::LEAVE_BALANCE_UNITS # => ["hours", "days", "weeks"]
```

`EARNINGS_TYPES`, `PAID_LEAVE_TYPES` and `ALLOWANCE_TYPES` are available for
both jurisdictions. Use their strings in your normal payslip hash; the lists
do not restrict input or add local enum/variant validation. The API may
accept a new code before this gem is updated. Printed-text fields such as
`tax_code` and `pay_cycle` are not code sets.

### Self-managed barcode flow

Use this flow when your application renders the barcode. This AU2 example is generated from
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
    employer_name: "Example Payroll Pty Ltd",
    employer_abn: "12 345 678 901",
    bsb: "062-000",
    account_number: "****5678",
    account_name: "Jane A Doe",
    address: {lines: ["12 Example St"], suburb: "Sydney", state_or_territory: "NSW", postcode: "2000"}
  },
  non_pii: {
    period_end: "2026-08-31",
    payment_date: "2026-09-04",
    currency: "AUD",
    gross: "9000.00",
    paygw: "2250.00",
    net: "6750.00"
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
prepared = Verifiabl::Issuer.prepare_australian_v2_payslip(
  pii: PAYSLIP.fetch(:pii),
  payslip_non_pii: PAYSLIP.fetch(:non_pii),
  issued_at: Time.now.utc,
  key: provider_encryption_key
)
# Persist prepared.registration and the binary ciphertext from
# prepared.barcode_parts(prepared.verifiabl_reference).fetch(:encrypted_pii)
# atomically before sending. Reuse both after a process restart.
result = issuer.register_non_pii(**prepared.registration)

barcode = Verifiabl::Issuer.build_barcode_svg(
  **prepared.barcode_parts(result.verifiabl_reference),
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

Use this alternative when Verifiabl should render the barcode PNG. This NZ2 example is
generated from the runnable
[`examples/issuer/basic/issue_payslips_api_managed.rb`](../../examples/issuer/basic/issue_payslips_api_managed.rb)
source.

<!-- snippet:ruby.api-managed-issuance:start -->

```ruby
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
```

<!-- snippet:ruby.api-managed-issuance:end -->

`register_and_build_barcode` sends the encrypted PII in addition to the non-PII fields and encryption
metadata. Verifiabl uses the ciphertext to render the returned PNG and does not retain it. Plaintext
PII is never sent in either flow.

### Retries and batches

For a self-managed registration that must remain retryable across process
restarts, persist `prepared.registration` and the binary ciphertext from
`prepared.barcode_parts(prepared.verifiabl_reference).fetch(:encrypted_pii)`
together before the first call. The registration includes the reference, IV and
tag but not the ciphertext. Reuse the *same* registration for a later attempt,
then render from the saved ciphertext and the returned reference. You can pass `verifiabl_reference:` to the preparation helper if your
system already allocated one. Do not prepare and encrypt again for an
idempotent replay. The API-managed request does not include this reference.

For pay runs, prepare each record with the matching jurisdiction helper. Pass
its `registration` hash to batch registration with an optional `external_id`.
Use each prepared result's `barcode_parts` with the corresponding batch result:

```ruby
prepared = payslips.map do |payslip|
  if payslip.fetch(:country) == "AU"
    Verifiabl::Issuer.prepare_australian_v2_payslip(
      pii: payslip.fetch(:pii), payslip_non_pii: payslip.fetch(:non_pii),
      issued_at: Time.now.utc, key: provider_encryption_key
    )
  else
    Verifiabl::Issuer.prepare_new_zealand_v2_payslip(
      pii: payslip.fetch(:pii), payslip_non_pii: payslip.fetch(:non_pii),
      issued_at: Time.now.utc, key: provider_encryption_key
    )
  end
end
# Persist each prepared reference, registration, and ciphertext before sending.
batch = issuer.register_non_pii_batch(prepared.each_with_index.map do |item, index|
  item.registration.merge(external_id: payslips.fetch(index).fetch(:external_id))
end)
batch.results.each_with_index do |item, index|
  if %w[created duplicate].include?(item.status)
    parts = prepared.fetch(index).barcode_parts(item.verifiabl_reference)
    # Render this record's barcode from parts.
  else
    # Handle item.code; do not parse item.detail.
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
