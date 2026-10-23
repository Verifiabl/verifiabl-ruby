# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/token_fixtures"

# Each client keeps its own token in memory, so every client here stands in
# for a separate process whose only link to the others is the shared store.
class SharedTokenStoreTest < Minitest::Test
  include TokenFixtures

  def test_workers_in_other_processes_reuse_the_stored_token
    transport = FakeTransport.new
    store = FakeStore.new

    3.times { register(worker(transport, store)) }

    assert_equal 1, transport.token_requests.length
    assert_equal ["Bearer token-1"] * 3, transport.authorizations
  end

  def test_the_store_holds_neither_the_token_nor_the_credentials
    store = FakeStore.new

    register(worker(FakeTransport.new, store))

    stored = store.entries.to_a.join
    %w[token-1 client secret].each { |plaintext| refute_includes stored, plaintext }
  end

  def test_workers_with_different_secrets_never_share_a_stored_token
    transport = FakeTransport.new
    store = FakeStore.new

    register(worker(transport, store, client_secret: "secret-a"))
    register(worker(transport, store, client_secret: "secret-b"))

    assert_equal 2, store.tokens.length
    assert_equal ["Bearer token-1", "Bearer token-2"], transport.authorizations
  end

  # The same secret in two environments must not let one environment's token
  # be served to the other: the keys are bound to the identity, and the entry
  # key is authenticated with the ciphertext.
  def test_an_entry_copied_to_another_key_is_not_served
    transport = FakeTransport.new
    store = FakeStore.new
    register(worker(transport, store, environment: :sandbox))
    register(worker(transport, store, environment: :production))
    sandbox_key, production_key = store.tokens.keys
    store.entries[production_key] = store.entries[sandbox_key]
    store.expire_claims

    register(worker(transport, store, environment: :production))

    assert_equal 3, transport.token_requests.length
    assert_equal "Bearer token-3", transport.authorizations.last
  end

  def test_a_tampered_entry_counts_as_a_miss
    transport = FakeTransport.new
    store = FakeStore.new
    register(worker(transport, store))
    key, value = store.tokens.first
    middle = value.length / 2
    tampered = value.dup
    tampered[middle] = (value[middle] == "A") ? "B" : "A"
    store.entries[key] = tampered
    store.expire_claims

    register(worker(transport, store))

    assert_equal ["Bearer token-1", "Bearer token-2"], transport.authorizations
  end

  def test_a_failing_store_does_not_block_registration
    transport = FakeTransport.new

    2.times { register(worker(transport, FailingStore.new)) }

    assert_equal ["Bearer token-1", "Bearer token-2"], transport.authorizations
  end

  def test_store_failures_are_reported_to_on_error
    events = []

    register(worker(FakeTransport.new, FailingStore.new, on_error: events.method(:<<)))

    assert_equal %i[read claim claim write], events.map { |event| event.fetch(:token_store) }
    assert events.all? { |event| event.fetch(:error).is_a?(IOError) }
    assert events.all?(&:frozen?)
  end

  def test_a_failing_on_error_hook_does_not_block_registration
    transport = FakeTransport.new
    failing_hook = ->(_event) { raise "hook failed" }

    register(worker(transport, FailingStore.new, on_error: failing_hook))

    assert_equal ["Bearer token-1"], transport.authorizations
  end

  def test_an_expired_entry_is_not_served
    transport = FakeTransport.new
    store = FakeStore.new
    now = Time.utc(2026, 10, 21)
    clock = -> { now }
    register(worker(transport, store, clock: clock))

    now += 3600
    store.expire_claims
    register(worker(transport, store, clock: clock))

    assert_equal ["Bearer token-1", "Bearer token-2"], transport.authorizations
  end

  def test_entries_expire_with_their_token
    store = FakeStore.new
    now = Time.utc(2026, 10, 21)

    register(worker(FakeTransport.new, store, clock: -> { now }))

    assert_equal [3600], store.expiries.values_at(*store.tokens.keys)
  end

  def test_a_rejected_token_is_replaced_in_the_store
    rejected = []
    transport = FakeTransport.new(rejected_tokens: rejected)
    store = FakeStore.new
    now = Time.utc(2026, 10, 21)
    clock = -> { now }
    register(worker(transport, store, clock: clock))
    rejected << "token-1"
    now += 61

    register(worker(transport, store, clock: clock))
    register(worker(transport, store, clock: clock))

    assert_equal ["Bearer token-1", "Bearer token-1", "Bearer token-2", "Bearer token-2"], transport.authorizations
    assert_equal 2, transport.token_requests.length
  end

  # The claim from the first fetch is still live, but nobody else is
  # fetching, so the replacement must not wait for it.
  def test_a_rejected_token_is_replaced_without_waiting_for_a_claim
    rejected = []
    transport = FakeTransport.new(rejected_tokens: rejected)
    sleeps = []
    now = Time.utc(2026, 10, 21)
    client = worker(transport, FakeStore.new, clock: -> { now }, sleeper: sleeps.method(:<<))
    register(client)
    rejected << "token-1"
    now += 61

    register(client)

    assert_empty sleeps
    assert_equal ["Bearer token-1", "Bearer token-1", "Bearer token-2"], transport.authorizations
  end

  # A replacement for a token rejected within a minute of its fetch would be
  # rejected too, once per request.
  def test_a_token_rejected_within_a_minute_of_its_fetch_is_not_replaced
    transport = FakeTransport.new(rejected_tokens: ["token-1"])
    client = worker(transport, FakeStore.new)

    2.times { assert_raises(Verifiabl::Issuer::ApiError) { register(client) } }

    assert_equal 1, transport.token_requests.length
    assert_equal ["Bearer token-1"] * 2, transport.authorizations
  end

  # Both workers hold the rejected token in memory. The second reads the
  # first one's replacement from the store instead of fetching another.
  def test_a_worker_whose_token_was_rejected_reads_the_replacement_from_the_store
    rejected = []
    transport = FakeTransport.new(rejected_tokens: rejected)
    store = FakeStore.new
    now = Time.utc(2026, 10, 21)
    clock = -> { now }
    first = worker(transport, store, clock: clock)
    second = worker(transport, store, clock: clock)
    register(first)
    register(second)
    rejected << "token-1"
    now += 61

    register(first)
    register(second)

    assert_equal 2, transport.token_requests.length
    assert_equal %w[token-1 token-1 token-1 token-2 token-1 token-2].map { |token| "Bearer #{token}" }, transport.authorizations
  end

  # Every worker finds the stored token due at the same moment. The one
  # holding the claim fetches the replacement that the others wait for.
  def test_workers_that_find_the_stored_token_due_wait_for_one_renewal
    fetcher_transport = FakeTransport.new
    waiter_transport = FakeTransport.new
    store = FakeStore.new
    now = Time.utc(2026, 10, 21)
    clock = -> { now }
    fetcher = worker(fetcher_transport, store, clock: clock)
    register(fetcher)
    store.expire_claims

    now += 3600 - 30
    claim_fetch(fetcher)
    waiter = worker(waiter_transport, store, clock: clock, sleeper: ->(_seconds) { fetcher.send(:fetch_and_share_token, deadline) })
    register(waiter)

    assert_equal 2, fetcher_transport.token_requests.length
    assert_empty waiter_transport.token_requests
    assert_equal ["Bearer token-2"], waiter_transport.authorizations
  end

  def test_a_worker_waits_for_the_process_that_claimed_the_fetch
    fetcher_transport = FakeTransport.new
    waiter_transport = FakeTransport.new
    store = FakeStore.new
    fetcher = worker(fetcher_transport, store)
    claim_fetch(fetcher)
    waiter = worker(waiter_transport, store, sleeper: ->(_seconds) { fetcher.send(:fetch_and_share_token, deadline) })

    register(waiter)

    assert_equal 1, fetcher_transport.token_requests.length
    assert_empty waiter_transport.token_requests
    assert_equal ["Bearer token-1"], waiter_transport.authorizations
  end

  # A worker whose token is due but still valid keeps using it while another
  # process fetches, and reads the new token once it is stored.
  def test_a_worker_keeps_its_valid_token_while_another_process_renews
    transport = FakeTransport.new
    store = FakeStore.new
    now = Time.utc(2026, 10, 21)
    clock = -> { now }
    sleeps = []
    renewing = worker(transport, store, clock: clock, sleeper: sleeps.method(:<<))
    register(renewing)
    store.expire_claims
    now += 3600 - 30
    claimant = worker(transport, store, clock: clock)
    claim_fetch(claimant)

    register(renewing)
    claimant.send(:fetch_and_share_token, deadline)
    register(renewing)

    assert_empty sleeps
    assert_equal ["Bearer token-1", "Bearer token-1", "Bearer token-2"], transport.authorizations
  end

  def test_a_worker_claims_the_fetch_itself_when_the_claim_lapses
    transport = FakeTransport.new
    store = FakeStore.new
    claim_fetch(worker(transport, store))
    elapsed = 0.0
    sleeper = lambda do |seconds|
      elapsed += seconds
      store.expire_claims if elapsed > 4.9
    end
    waiter = worker(transport, store, monotonic_clock: -> { elapsed }, sleeper: sleeper)

    register(waiter)

    assert_in_delta 5.5, elapsed
    assert_equal ["Bearer token-1"], transport.authorizations
  end

  # A claim that outlives its fetch must expire before a one-minute token is
  # due, 30 seconds after the fetch.
  def test_a_claim_lasts_as_long_as_the_token_request
    store = FakeStore.new

    register(worker(FakeTransport.new(expires_in: 60), store, timeout: 120))

    claim_key = store.entries.keys.find { |key| !store.tokens.key?(key) }
    assert_equal Verifiabl::Issuer::Client::TOKEN_FETCH_TIMEOUT_SECONDS, store.expiries.fetch(claim_key)
  end

  # Each store call here takes a second. The claim and the token request
  # must still end together, or a second process could claim mid-fetch.
  def test_the_claim_and_the_token_request_share_one_deadline
    transport = FakeTransport.new
    token_timeouts = []
    recording = lambda do |**request|
      token_timeouts << request.fetch(:timeout) if request.fetch(:url).include?("/oauth/token")
      transport.call(**request)
    end
    store = FakeStore.new
    elapsed = 0.0
    slow = SlowStore.new(store) { elapsed += 1 }

    register(worker(recording, slow, monotonic_clock: -> { elapsed }))

    claim_key = store.entries.keys.find { |key| !store.tokens.key?(key) }
    assert_equal [8], token_timeouts
    assert_equal 9, store.expiries.fetch(claim_key)
  end

  def test_a_waiting_worker_polls_less_often_over_time
    transport = FakeTransport.new
    store = FakeStore.new
    claim_fetch(worker(transport, store))
    elapsed = 0.0
    sleeps = []
    sleeper = lambda do |seconds|
      sleeps << seconds
      elapsed += seconds
    end
    waiter = worker(transport, store, timeout: 4, monotonic_clock: -> { elapsed }, sleeper: sleeper)

    assert_raises(Verifiabl::Issuer::TimeoutError) { register(waiter) }

    assert_equal [0.1, 0.2, 0.4, 0.8, 1.0, 1.0], sleeps.first(6)
    assert_in_delta 0.5, sleeps.last
  end

  # No store read starts once the request's time is up.
  def test_the_wait_for_a_claimed_fetch_ends_at_the_request_deadline
    transport = FakeTransport.new
    store = FakeStore.new
    claim_fetch(worker(transport, store))
    elapsed = 0.0
    store_calls_at = []
    timed = SlowStore.new(store) { store_calls_at << elapsed }
    waiter = worker(transport, timed, timeout: 1, monotonic_clock: -> { elapsed }, sleeper: ->(seconds) { elapsed += seconds })

    assert_raises(Verifiabl::Issuer::TimeoutError) { register(waiter) }

    assert_in_delta 1.0, elapsed
    assert store_calls_at.all? { |at| at < 1.0 }
    assert_empty transport.token_requests
  end

  # The claim read, write and read-back are separate store calls, so the
  # budget is checked between them.
  def test_a_slow_claim_write_that_exhausts_the_budget_is_not_read_back
    transport = FakeTransport.new
    store = FakeStore.new
    claim_fetch(worker(transport, store))
    store.expire_claims
    elapsed = 0.0
    store_calls = 0
    slow = SlowStore.new(store) do
      store_calls += 1
      elapsed += 0.4
    end
    client = worker(transport, slow, timeout: 1, monotonic_clock: -> { elapsed }, sleeper: ->(seconds) { elapsed += seconds })
    claim_fetch(worker(transport, store))

    assert_raises(Verifiabl::Issuer::TimeoutError) { register(client) }

    assert_equal 3, store_calls
    assert_empty transport.token_requests
  end

  # A store that fails while a worker waits cannot say whether the claim is
  # still held, so the worker fetches its own token at the next poll.
  def test_a_store_that_fails_during_the_wait_ends_the_wait
    transport = FakeTransport.new
    store = FakeStore.new
    claim_fetch(worker(transport, store))
    failing = FailingReadsStore.new(store)
    elapsed = 0.0
    events = []
    sleeper = lambda do |seconds|
      failing.failing = true
      elapsed += seconds
    end
    waiter = worker(transport, failing, on_error: events.method(:<<), monotonic_clock: -> { elapsed }, sleeper: sleeper)

    register(waiter)

    assert_in_delta Verifiabl::Issuer::Client::SHARED_FETCH_POLL_SECONDS, elapsed
    assert_equal ["Bearer token-1"], transport.authorizations
    assert_equal %i[read claim claim], events.map { |event| event.fetch(:token_store) }
  end

  def test_a_claim_the_store_could_not_record_does_not_wait
    transport = FakeTransport.new
    sleeps = []

    register(worker(transport, SwallowingClaimStore.new, sleeper: sleeps.method(:<<)))

    assert_empty sleeps
    assert_equal ["Bearer token-1"], transport.authorizations
  end

  # A store that swallows a backend error can answer `false` for the claim,
  # as if another process held it. The claim does not read back, so the
  # process fetches instead of waiting.
  def test_a_claim_that_does_not_read_back_does_not_wait
    transport = FakeTransport.new
    sleeps = []

    register(worker(transport, UnreadableClaimStore.new, sleeper: sleeps.method(:<<)))

    assert_empty sleeps
    assert_equal ["Bearer token-1"], transport.authorizations
  end

  def test_credentials_changed_after_construction_do_not_reach_the_store_or_the_token_request
    transport = FakeTransport.new
    store = FakeStore.new
    secret = +"secret"
    client = worker(transport, store, client_secret: secret)
    secret.replace("other-secret")

    register(client)
    register(worker(transport, store, client_secret: "secret"))

    assert_equal ["secret"], transport.token_requests.map { |request| request.fetch("client_secret") }
    assert_equal ["Bearer token-1", "Bearer token-1"], transport.authorizations
  end

  # The store call cannot be interrupted, so the budget is checked after it.
  def test_a_slow_store_counts_against_the_request_timeout
    transport = FakeTransport.new
    elapsed = 0.0
    store_calls = 0
    store = SlowStore.new(FakeStore.new) do
      store_calls += 1
      elapsed += 10
    end
    client = worker(transport, store, timeout: 5, monotonic_clock: -> { elapsed }, sleeper: ->(seconds) { elapsed += seconds })

    assert_raises(Verifiabl::Issuer::TimeoutError) { register(client) }

    assert_equal 1, store_calls
    assert_empty transport.token_requests
    assert_empty transport.authorizations
  end

  def test_a_token_read_past_the_deadline_is_kept_for_the_next_request
    store = FakeStore.new
    register(worker(FakeTransport.new, store))
    transport = FakeTransport.new
    elapsed = 0.0
    slow = SlowStore.new(store) { elapsed += 10 }
    client = worker(transport, slow, timeout: 5, monotonic_clock: -> { elapsed }, sleeper: ->(seconds) { elapsed += seconds })

    assert_raises(Verifiabl::Issuer::TimeoutError) { register(client) }
    register(client)

    assert_empty transport.token_requests
    assert_equal ["Bearer token-1"], transport.authorizations
  end

  # The store read takes wall-clock time, so a token that was fresh when the
  # read started can have expired by the time it returns.
  def test_a_token_that_expires_during_the_store_read_is_not_served
    transport = FakeTransport.new
    store = FakeStore.new
    now = Time.utc(2026, 10, 21)
    clock = -> { now }
    register(worker(transport, store, clock: clock))
    store.expire_claims
    slow = SlowStore.new(store) { now += 3600 }

    register(worker(transport, slow, clock: clock))

    assert_equal 2, transport.token_requests.length
    assert_equal "Bearer token-2", transport.authorizations.last
  end

  # A 60-second token renews 30 seconds before expiry. Dated from before a
  # 20-second read, it would look stale as soon as it was fetched.
  def test_a_token_fetched_after_a_slow_miss_is_dated_from_the_fetch
    transport = FakeTransport.new(expires_in: 60)
    now = Time.utc(2026, 10, 21)
    store = SlowStore.new(FakeStore.new) { now += 20 }
    client = worker(transport, store, clock: -> { now })

    2.times { register(client) }

    assert_equal 1, transport.token_requests.length
    assert_equal ["Bearer token-1"] * 2, transport.authorizations
  end

  def test_a_store_without_the_cache_methods_is_rejected
    error = assert_raises(ArgumentError) { worker(FakeTransport.new, Object.new) }

    assert_equal "token_store must respond to read and write", error.message
  end

  private

  def worker(transport, store, **options)
    build_client(transport, token_store: store, **options)
  end

  def register(client)
    client.register_non_pii(verifiabl_reference: REFERENCE, **registration)
  end

  def claim_fetch(client)
    assert client.instance_variable_get(:@shared_token_store).claim_fetch(2)
  end
end
