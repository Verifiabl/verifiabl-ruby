# Changelog

All notable changes to the Verifiabl Ruby SDK will be documented in this file.

## Unreleased

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
