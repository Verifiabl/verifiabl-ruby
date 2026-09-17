# Changelog

All notable changes to the Verifiabl Ruby SDK will be documented in this file.

## Unreleased

## [0.1.0-rc.1] - 2026-09-17

- Generate Ruby PII profile constants, QR frame policy, frame assets, and renderer parity fixtures from canonical cross-SDK tooling, and add Ruby CodeQL coverage.
- **Breaking:** expose and accept ciphertext, AES-GCM IV, and authentication tag values as binary strings. The SDK now applies base64url only at the issuer API boundary and Base32 at the v2 barcode and XMP boundary, allowing callers to persist encrypted values directly in binary database columns.
- Add a runnable self-managed issuance example and generated, drift-checked usage documentation.
- Add deterministic SVG and PNG barcode renderers using the official cross-SDK frame assets, rounded finder compositor, error-correction ladder, and fixed raster widths.
- Add cross-SDK-compatible mixed-mode QR matrix generation with canonical mask selection.
- Add Ruby to the shared cross-ecosystem QR qualification tooling.
- Add the framework-neutral issuer HTTP client with OAuth token caching, single-flight refresh, 401 refresh, idempotency-aware retries, and typed errors.
- Generate or accept a provider reference for single registration so ambiguous failures can be retried safely.
- Apply one overall request deadline across OAuth, refresh, retries, and backoff.
- Validate endpoint overrides, registration requests, successful responses, and correlated batch results.
- Add explicit, thread-safe client construction, fork-aware OAuth token caching, and framework-neutral observability callbacks.
- Add checked RBS signatures and isolated packed-gem consumer qualification.
- Support Ruby 3.3 through Ruby 4.0.
