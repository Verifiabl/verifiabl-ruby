# Verifiabl Ruby SDKs

Official Ruby SDKs for [Verifiabl](https://verifiabl.io). This repository is organised as a
multi-gem workspace so each SDK can be versioned and published independently.

## Gems

- [`verifiabl-issuer`](./gems/verifiabl-issuer) — format and encrypt payslip PII, register non-PII
  data, and render Verifiabl QR codes.

See the issuer gem's [README](./gems/verifiabl-issuer/README.md) for installation and usage.

## Examples

Issuer examples are under [`examples/issuer`](./examples/issuer).

## Development

```sh
bundle install
bundle exec rake
(cd gems/verifiabl-issuer && bundle exec gem build verifiabl-issuer.gemspec)
bundle exec ruby script/packed_gem_check.rb
```

## License

[MIT](./LICENSE)
