# Changelog

All notable changes to the Verifiabl Ruby SDK will be documented in this file.

## Unreleased

## [0.3.0] - 2026-10-04

- Accept an `other` earnings line in AU2 and NZ2 payslips, for a pay code that
  fits no other earnings type.

## [0.2.0] - 2026-10-04

- Add `four_weekly` and `semi_monthly` to the AU2 `PAY_FREQUENCIES`.

## [0.1.0] - 2026-09-30

- First stable release of the Ruby issuer SDK. Keep the AU/NZ v2 preparation
  helpers, registration and QR rendering behaviour from the release candidates.
- Clarify that the verifier currently interprets AU2 and NZ2 as structured PII
  only for `au.payslip.v2` and `nz.payslip.v2`. Future non-PII schemas need an
  explicit verifier reader update before issuance.

## [0.1.0-rc.5] - 2026-09-29

- Add `prepare_australian_v2_payslip` and `prepare_new_zealand_v2_payslip`
  to keep each jurisdiction's PII profile, v2 registration and encrypted
  ciphertext together. Prepared registration and barcode outputs are independent
  copies; API-managed requests omit the caller reference.
- Use remaining-budget I/O timeouts and deadline-aware token-lock waits instead
  of asynchronously interrupting HTTP transports. Built-in Net::HTTP I/O
  timeouts are per operation, not a strict end-to-end wall-clock limit.

## [0.1.0-rc.4] - 2026-09-28

- **Breaking:** AU2 and NZ2 amounts, rates and quantities are now plain decimal Strings, for
  example `gross: "1234.56"`, instead of `{value:, display:}` hashes. `display` is removed. The SDK
  rejects any other value, including an `Integer`, `Float` or `BigDecimal`, before transport and sends
  each String exactly as given.
- **Breaking:** remove `Verifiabl::Issuer.payslip_number`.
- **Breaking:** `currency` is required for `au.payslip.v2` and `nz.payslip.v2`, and
  `SUPPORTED_V2_CURRENCIES` now lists the 155 current ISO 4217 currency codes instead of ten codes.
  Fund codes and codes with no minor unit (for example `XAU`, `XTS`, `XXX`) are excluded, because
  wages are paid in legal tender.
  v1 schemas are unchanged.

## [0.1.0-rc.3] - 2026-09-28

- Reject unlisted AU/NZ v2 non-PII fields (including nested fields) before transport;
  the API validates field values. Batch reports local field-guard errors per record.
- Add AU2 and NZ2 encrypted PII writers with structured address inputs, fixed eight-position
  output, jurisdiction-specific profile identifiers, and the shared 1024-byte limit.
- Add v2 schema identifiers, numeric `{ value, display? }` formatting from `Integer`, `Float`,
  `BigDecimal` or a decimal string, and the optional ten-currency allow-list, which registration
  enforces for `au.payslip.v2` and `nz.payslip.v2`.
- Make `period_start` optional for `au.payslip.v2` and `nz.payslip.v2` while retaining it for v1.
- **Breaking:** remove internal QR and scan-URL intermediate result types from
  the supported RBS surface. `Client` still accepts a custom `transport` for
  test doubles and HTTP adapters; timing and retry dependencies are internal.

## [0.1.0-rc.2] - 2026-09-17

- Add a direct RubyGems link to the customer documentation.
- Correct the installation instructions for the release candidate.

## [0.1.0-rc.1] - 2026-09-17

- Add the official Ruby issuer client for single and batch payslip registration, with OAuth token caching, safe retries, request deadlines, validation, and observability hooks.
- Add compatible PII encryption and Verifiabl v2 QR generation with SVG and PNG rendering using the official frame assets.
- Add runnable API-managed and self-managed issuance examples.
- Support Ruby 3.3 through Ruby 4.0 with checked RBS signatures.
