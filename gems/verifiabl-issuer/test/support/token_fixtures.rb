# frozen_string_literal: true

require "json"

# A fake token endpoint and client builder shared by the token tests.
module TokenFixtures
  REFERENCE = "AbCdEfGhIjKlMnOpQrStUv"

  class FakeTransport
    attr_reader :token_requests, :authorizations

    # rejected_tokens: access tokens the issuer API answers with a 401.
    # expires_in: the lifetime, in seconds, of each token it issues.
    # token_delay: seconds each token request takes, for a slow endpoint.
    def initialize(rejected_tokens: [], expires_in: 3600, token_delay: 0)
      @mutex = Mutex.new
      @token_requests = []
      @authorizations = []
      @rejected_tokens = rejected_tokens
      @expires_in = expires_in
      @token_delay = token_delay
    end

    def call(url:, headers:, body:, **)
      return token_response(body) if url.include?("/oauth/token")

      authorization = headers.fetch("authorization")
      @mutex.synchronize { @authorizations << authorization }
      return respond(401, code: "UNAUTHORIZED", error: "token rejected") if @rejected_tokens.include?(authorization.delete_prefix("Bearer "))

      respond(200, verifiabl_reference: TokenFixtures::REFERENCE)
    end

    private

    def token_response(body)
      sleep(@token_delay) if @token_delay.positive?
      number = @mutex.synchronize do
        @token_requests << JSON.parse(body)
        @token_requests.length
      end
      respond(200, access_token: "token-#{number}", token_type: "Bearer", expires_in: @expires_in)
    end

    def respond(status, body)
      Verifiabl::Issuer::Client::Response.new(status: status, headers: {}, body: JSON.generate(body))
    end
  end

  # Matches the Active Support cache store methods the client calls,
  # including `unless_exist:`, but never expires an entry.
  class FakeStore
    attr_reader :entries, :expiries

    def initialize
      @entries = {}
      @expiries = {}
    end

    def read(key)
      @entries[key]
    end

    def write(key, value, expires_in:, unless_exist: false)
      return false if unless_exist && @entries.key?(key)

      @expiries[key] = expires_in
      @entries[key] = value
      true
    end

    # Token entries, without fetch claims.
    def tokens
      @entries.reject { |key, _| fetch_claim?(key) }
    end

    # Stands in for the claims' two-second expiry.
    def expire_claims
      @entries.delete_if { |key, _| fetch_claim?(key) }
    end

    private

    def fetch_claim?(key)
      key.end_with?(Verifiabl::Issuer::SharedTokenStore::FETCH_CLAIM_SUFFIX)
    end
  end

  # Returns nil for a claim, as an Active Support store does when its error
  # handler swallows a backend failure.
  class SwallowingClaimStore < FakeStore
    def write(key, value, expires_in:, unless_exist: false)
      return if unless_exist

      super
    end
  end

  # Answers false for a claim without storing it, as Rails 7.0 and 7.1
  # stores and Solid Cache do when they swallow a backend failure.
  class UnreadableClaimStore < FakeStore
    def write(key, value, expires_in:, unless_exist: false)
      return false if unless_exist

      super
    end
  end

  class FailingStore
    def read(_key)
      raise IOError, "cache unavailable"
    end

    def write(_key, _value, expires_in:, unless_exist: false)
      raise IOError, "cache unavailable"
    end
  end

  # Wraps a store whose reads can be made to fail part way through a test,
  # as when a cache goes down while a worker waits for another's token.
  class FailingReadsStore
    attr_accessor :failing

    def initialize(store)
      @store = store
      @failing = false
    end

    def read(key)
      raise IOError, "cache unavailable" if @failing

      @store.read(key)
    end

    def write(key, value, **options)
      @store.write(key, value, **options)
    end
  end

  # Wraps a store so every call takes time on the test's monotonic clock.
  class SlowStore
    def initialize(store, &elapse)
      @store = store
      @elapse = elapse
    end

    def read(key)
      @elapse.call
      @store.read(key)
    end

    def write(key, value, **options)
      @elapse.call
      @store.write(key, value, **options)
    end
  end

  def build_client(transport, client_id: "client", client_secret: "secret", environment: :sandbox, token_store: nil, on_error: nil, timeout: 30, **runtime)
    configuration = Verifiabl::Issuer::Configuration.new(
      client_id: client_id,
      client_secret: client_secret,
      environment: environment,
      token_store: token_store,
      on_error: on_error,
      timeout: timeout
    )
    client = Verifiabl::Issuer::Client.new(configuration, transport: transport)
    client.send(:configure_runtime_dependencies, transport: transport, **runtime) unless runtime.empty?
    client
  end

  def deadline
    Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
  end

  def registration
    {
      schema: "au.payslip.v2",
      issued_at: "2026-06-11T00:00:00Z",
      payslip_non_pii: {period_start: "2026-06-01", period_end: "2026-06-15", payment_date: "2026-06-18",
                        currency: "AUD", gross: "1234.56", paygw: "234.56", net: "1000.00"},
      encryption_metadata: {iv: "\0".b * 12, tag: "\0".b * 16}
    }
  end
end
