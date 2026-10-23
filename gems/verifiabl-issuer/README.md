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

Each client fetches an OAuth token and keeps it in memory, so each process fetches its own token.
If you run many worker processes, for example an autoscaled job queue, set `token_store:` to a
cache that the processes share. In a Rails application, use `Rails.cache` if Redis, Memcached or
Solid Cache stores its data:

```ruby
configuration = Verifiabl::Issuer::Configuration.new(
  client_id: ENV.fetch("VERIFIABL_CLIENT_ID"),
  client_secret: ENV.fetch("VERIFIABL_CLIENT_SECRET"),
  token_store: Rails.cache
)
```

You can also use a different Active Support cache store, or any object with `read(key)` and
`write(key, value, expires_in:, unless_exist: false)`. With `unless_exist: true`, `write` must
write only if the key is absent, and return `false` if the key exists.

The client encrypts each token with a key derived from the client secret before it writes the
token. It names the entry with a keyed hash. The cache never holds a usable token or the client
credentials.

Each process uses its in-memory token. It reads the store only when that token is due for
renewal, one minute before it expires. When the stored token is missing or due, one process
claims the fetch and fetches a new token. The claim is an `unless_exist: true` write that lasts
for 10 seconds, the limit of the token request. While that process fetches:

- A process with a valid token continues to use it until the new token is in the store.
- A process with no valid token polls the store for the new token. The interval starts at 0.1
  seconds and doubles to a maximum of one second. If the claim expires, that process claims the
  fetch.

A fleet that renews together, or starts together after a quiet period, therefore fetches one
token. When the API rejects a token, the client fetches a new token immediately. If the client
fetched the rejected token less than one minute before, it returns the 401 instead.

Limits:

- A store failure costs a token fetch, not a registration. `Rails.cache` catches backend errors
  and sends them to the Rails error reporter and logger, so `on_error` does not get them. To get
  them in `on_error`, as an event with `token_store:` (`:read`, `:write` or `:claim`) and
  `error:`, give the SDK a different store with an `error_handler:` that raises the exception
  again. Do not make `Rails.cache` raise.
- If the process that holds the claim stops during its fetch, the processes with no token wait
  until the claim expires, at most 10 seconds.
- The SDK cannot interrupt a store call. It checks the request's time budget after each call,
  and store calls run while the client holds its token lock. Keep the store timeouts short. The
  Rails Redis store default is one second.
- The claim is best effort. If the store has no atomic `unless_exist`, such as a file store,
  several processes can fetch. A store that is local to each process, such as a memory store,
  shares nothing.
- Stored expiry times are absolute. Keep worker clocks within one minute of each other.

A store event has only `token_store:` and `error:`. A request failure has `method:`, `url:`,
`path:` and `elapsed_ms:`. Check the kind of event before you read its fields. The SDK ignores
exceptions from `on_error`, so if your handler fails on a store event, the report is lost:

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

## License

MIT. See [LICENSE](https://github.com/Verifiabl/verifiabl-ruby/blob/main/gems/verifiabl-issuer/LICENSE).
