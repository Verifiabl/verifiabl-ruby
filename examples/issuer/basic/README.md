# Basic issuer examples

These examples demonstrate the two alternative barcode flows with the same fictional `PAYSLIP`
fixture. Both format and encrypt PII locally and register only the non-PII fields as payslip data.
They support Ruby 3.3 and newer.

## Setup

Install the released gem from RubyGems:

```sh
gem install verifiabl-issuer
cd examples/issuer/basic
bundle install
```

When validating an unpublished checkout, build and install its package first:

```sh
(cd gems/verifiabl-issuer && gem build verifiabl-issuer.gemspec --output ../../verifiabl-issuer.gem)
gem install ./verifiabl-issuer.gem
cd examples/issuer/basic
bundle install
```

## Run

Export your sandbox credentials and provider encryption key. The encryption key must be a
Base64-encoded 32-byte key.

```sh
export VERIFIABL_CLIENT_ID='your-sandbox-client-id'
export VERIFIABL_CLIENT_SECRET='your-sandbox-client-secret'
export VERIFIABL_ENCRYPTION_KEY_BASE64='your-base64-encoded-provider-key'
```

Run the self-managed flow to register the payslip and render its SVG locally:

```sh
ruby issue_payslips_self_managed.rb
```

Alternatively, run the API-managed flow to register the payslip and download the PNG rendered by
Verifiabl:

```sh
ruby issue_payslips_api_managed.rb
```

Each successful run prints the registered payslip's Verifiabl reference and writes its barcode under
`output/`. Each command creates a separate registration; choose one flow rather than running both
for the same real payslip.

The example Gemfile contains development tooling only. SDK validation builds and installs the packed
gem in an isolated gem home before checking these sources, so it cannot accidentally load the
checkout through a relative path.
