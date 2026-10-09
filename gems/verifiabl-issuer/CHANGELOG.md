# Changelog

All notable changes to the Verifiabl Ruby SDK will be documented in this file.

## Unreleased

## [0.5.0] - 2026-10-09

### Added

- AU2 `lump_sum` earnings lines accept `lump_sum_type`
  (`PayslipCodes::Australian::LUMP_SUM_TYPES`: `a_redundancy` for STP lump sum
  A type R, `a_other` for A type T, `b`, `d` or `e`), and a new `etp` line takes
  `etp_type` (`PayslipCodes::Australian::ETP_TYPES`: `redundancy` for ETP code
  R, `other` for O, `redundancy_split` for S, `other_split` for P,
  `death_dependant` for D, `death_non_dependant` for N,
  `death_non_dependant_split` for B or `death_trustee` for T) and
  `etp_component` (`PayslipCodes::Australian::ETP_COMPONENTS`: `taxable` or
  `tax_free`). Send the taxable and tax-free components as separate `etp`
  lines; tax withheld from an ETP is part of `paygw`. Lump sum W stays
  `return_to_work`, and lump sum U stays `paid_leave` with
  `unused_on_termination`. The gem sends a `lump_sum` line without a type, and
  the API accepts that for now. It will require `lump_sum_type` before
  production, once every issuer is on an SDK release with the lump sum codes.

### Removed

- **Breaking:** removed `au.payslip.v1` and `nz.payslip.v1` registration
  validation. The gem no longer requires `period_start` for those schemas; it
  sends them like any other schema without a field tree, and the issuer API
  rejects them. Send `au.payslip.v2` instead, for example with
  `Verifiabl::Issuer.prepare_australian_v2_payslip`.
- **Breaking:** removed the P2 PII writer `Verifiabl::Issuer.format_pii`.
  Verifiabl now accepts only the AU2 and NZ2 PII formats from issuers. Use
  `prepare_australian_v2_payslip` or `prepare_new_zealand_v2_payslip`, or for
  low-level use `format_australian_pii` or `format_new_zealand_pii` with
  `encrypt_pii`. Payslips already issued with P1 or P2 still verify.

## [0.4.0] - 2026-10-07

- Add `layout: :horizontal` to local SVG and PNG rendering, with the QR on the
  left, a 7-unit white gap and an opaque light-tinted brand panel on the right.
  SVG minimum/default width is 940; PNG supports 940, 1410, 1880 and 2820 pixels
  (default 1410). Vertical stays the default with unchanged output.
- Qualify horizontal SVG bytes, PNG pixels and QR metadata against Node and .NET,
  including independent digital decoding.

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
