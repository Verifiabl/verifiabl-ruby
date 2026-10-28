# verifiabl-issuer

The Verifiabl issuer SDK for Ruby. It registers payslip records with Verifiabl and makes their QR codes.

## Documentation

- [Issuer SDK guide](https://docs.verifiabl.io/issuer-sdk?lang=ruby)
- [API reference](https://docs.verifiabl.io/api-reference/sdks/ruby)

## Requirements

Ruby 3.3 or newer.

## Installation

```sh
gem install verifiabl-issuer
```

## Usage

Create one client with the client ID and client secret from your onboarding:

```ruby
require "verifiabl/issuer"

configuration = Verifiabl::Issuer::Configuration.new(
  environment: :sandbox,
  client_id: ENV.fetch("VERIFIABL_CLIENT_ID"),
  client_secret: ENV.fetch("VERIFIABL_CLIENT_SECRET")
)
issuer = Verifiabl::Issuer::Client.new(configuration)
```

### Share tokens between processes

Each process fetches its own OAuth token. To share one token between worker processes, set
`token_store:` to a cache that the processes share:

```ruby
configuration = Verifiabl::Issuer::Configuration.new(
  client_id: ENV.fetch("VERIFIABL_CLIENT_ID"),
  client_secret: ENV.fetch("VERIFIABL_CLIENT_SECRET"),
  token_store: Rails.cache
)
```

Not every store stops several processes from fetching at once. Before you choose a store, read
[Share tokens between worker processes](https://docs.verifiabl.io/issuer-sdk?lang=ruby#share-tokens-between-worker-processes).

If the store raises an error, `on_error` gets an event with only `token_store:` and `error:`.
Check the kind of event before you read its fields:

```ruby
on_error = lambda do |event|
  if event.key?(:token_store)
    logger.warn("Verifiabl token store #{event[:token_store]} failed: #{event[:error].class}")
  else
    logger.error("Verifiabl #{event[:method]} #{event[:path]} failed: #{event[:error].class}")
  end
end
```

To prepare and register payslips and make their QR codes, follow the [issuer SDK guide](https://docs.verifiabl.io/issuer-sdk?lang=ruby).

Before the first send, save each prepared `registration` and its ciphertext together. After a failure or restart, send that saved registration unchanged. It carries its reference, so the API does not register it twice. Preparing the payslip again makes a new reference. An `api_managed_registration` has no reference, so do not resend it after an ambiguous failure. See [Register again later](https://docs.verifiabl.io/issuer-sdk/retries-and-timeouts?lang=ruby#register-again-later).

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
(remaining seconds), for both OAuth and issuer requests. The OAuth token request gets at most
10 seconds. Return an object with integer `status`,
`headers` (prefer lowercase keys), and string `body` readers. Adapters own their I/O and
pool-acquisition timeouts, failed-connection cleanup, and must not retry non-idempotent calls.
For a **strict total deadline**, bring an adapter that bounds DNS, pool waits, TLS, writes, headers,
and the complete body by the remaining `timeout:` budget (including trickling responses). The SDK
cannot forcibly interrupt arbitrary blocking adapter code. Native `Timeout::Error` subclasses
become SDK `TimeoutError`; socket/I/O failures become SDK errors. The application owns adapter
shutdown, thread safety, and post-fork recreation.

## Support

Report issues at [github.com/Verifiabl/verifiabl-ruby](https://github.com/Verifiabl/verifiabl-ruby/issues).

## Verifying a release

The release workflow attests each gem's build provenance before publishing it, and RubyGems.org
serves the published bytes unchanged. Verify a gem with the [GitHub CLI](https://cli.github.com/).
Attestations are signed with Sigstore, recorded in its public transparency log, and stored with the
`Verifiabl/verifiabl-ruby` repository; they do not expire with workflow artifacts.

```sh
VERSION='<release version, for example 0.1.0-rc.1>'
RUBYGEMS_VERSION="$(ruby -rrubygems -e 'puts Gem::Version.new(ARGV.fetch(0))' "$VERSION")"
gem fetch verifiabl-issuer --version "$RUBYGEMS_VERSION"
gh attestation verify "verifiabl-issuer-$RUBYGEMS_VERSION.gem" \
  --repo Verifiabl/verifiabl-ruby \
  --signer-workflow Verifiabl/verifiabl-ruby/.github/workflows/release.yml \
  --source-ref "refs/tags/issuer/v$VERSION" \
  --deny-self-hosted-runners
```

Release tags use the SemVer version; RubyGems normalizes prereleases, so `0.1.0-rc.1` is published
as `0.1.0.pre.rc.1`.

## License

MIT. See [LICENSE](https://github.com/Verifiabl/verifiabl-ruby/blob/main/gems/verifiabl-issuer/LICENSE).
