# Verifiabl Ruby SDKs

Official Ruby SDKs for [Verifiabl](https://verifiabl.io). This repository is organised as a
multi-gem workspace so each SDK can be versioned and published independently.

## Gems

- [`verifiabl-issuer`](./gems/verifiabl-issuer) — format and encrypt payslip PII, register non-PII
  data, and render Verifiabl QR codes.

See the issuer gem's [README](./gems/verifiabl-issuer/README.md) for installation and usage.

## Examples

Issuer examples are under [`examples/issuer`](./examples/issuer).

The recommended v2 path is `Verifiabl::Issuer.prepare_australian_v2_payslip` or
`prepare_new_zealand_v2_payslip`. Each validates the jurisdiction's non-PII
fields, formats matching PII and encrypts locally. Send `prepared.registration`
to `register_non_pii` (or use it as a batch record), then render with
`prepared.barcode_parts(result.verifiabl_reference)`. Alternatively send
`prepared.api_managed_registration` to `register_and_build_barcode`. See
[`examples/issuer/prepare_v2.rb`](examples/issuer/prepare_v2.rb). Persist the
self-managed reference and registration for retries; the API-managed endpoint
allocates its own reference and cannot deduplicate ambiguous failures. Never
log or persist plaintext. Existing low-level APIs remain available.

## Development

```sh
bundle install
bundle exec rake
(cd gems/verifiabl-issuer && bundle exec gem build verifiabl-issuer.gemspec)
bundle exec ruby script/packed_gem_check.rb
```

### Generated API reference

The public API reference is generated with the pinned [YARD](https://yardoc.org/) dependency. The RBS
signature defines the supported public surface, and YARD supplies documentation from the Ruby source.
Generate the deterministic catalogue with:

```sh
bundle exec ruby script/api_reference.rb
```

The command replaces `generated/api/ruby.json`. The catalogue is checked in so the customer docs can
import an exact SDK revision without running Ruby or accessing this repository at build time. The
default Rake task runs the non-mutating freshness check; it can also be run directly:

```sh
bundle exec ruby script/api_reference.rb --check
```

## License

[MIT](./LICENSE)
