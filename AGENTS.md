# Verifiabl Ruby SDK

## Rules

- Keep gems under `gems/`. The issuer SDK is `gems/verifiabl-issuer`.
- Support Ruby 3.3 and newer. Do not add Rails or Active Support dependencies or integration layers.
- Use `rqrcode_core` for QR matrices. Keep deterministic SVG and PNG rendering in Verifiabl code.
- Keep this exported repository self-contained.
- Do not edit generated PII profiles, fixtures, QR widths or frame assets.
- Use synthetic data. Do not log payslip values, keys or credentials.

## Checks

Run commands from this ecosystem root. Report checks not run.

```sh
bundle install
bundle exec standardrb
bundle exec rake metrics
bundle exec rake test
bundle exec rbs -r bigdecimal -I gems/verifiabl-issuer/sig validate
bundle exec ruby script/api_reference.rb --check
(cd gems/verifiabl-issuer && bundle exec gem build verifiabl-issuer.gemspec)
bundle exec ruby script/packed_gem_check.rb
```

## Required reading

Read the relevant documents before edits.

| Task | Read |
| --- | --- |
| Development or API reference | [README](README.md) |
| Issuer API, validation or wire contracts | [Issuer README](gems/verifiabl-issuer/README.md) |
| Examples | [Example guide](examples/issuer/basic/README.md) |
| Packages or releases | Local `.github/workflows/` files and issuer gemspec |
