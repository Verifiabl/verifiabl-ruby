# frozen_string_literal: true

require "active_support"
require "active_support/cache"
require "active_support/cache/redis_cache_store"
require "securerandom"
require "socket"
require_relative "test_helper"
require_relative "support/token_fixtures"

# Runs the token store against real Active Support cache stores, which the
# other token tests replace with fakes. Tests that share tokens between
# processes need a Redis server and run when REDIS_URL is set, as in CI.
class TokenStoreIntegrationTest < Minitest::Test
  include TokenFixtures

  def test_a_memory_store_shares_a_token_between_clients
    transport = FakeTransport.new
    store = ActiveSupport::Cache::MemoryStore.new

    2.times { register(build_client(transport, token_store: store)) }

    assert_equal 1, transport.token_requests.length
    assert_equal ["Bearer token-1"] * 2, transport.authorizations
  end

  def test_a_memory_store_makes_a_worker_wait_for_the_claimed_fetch
    fetcher_transport = FakeTransport.new
    waiter_transport = FakeTransport.new
    store = ActiveSupport::Cache::MemoryStore.new
    fetcher = build_client(fetcher_transport, token_store: store)
    assert fetcher.instance_variable_get(:@shared_token_store).claim_fetch(2)
    waiter = build_client(waiter_transport, token_store: store, sleeper: ->(_seconds) { fetcher.send(:fetch_and_share_token, deadline) })

    register(waiter)

    assert_equal 1, fetcher_transport.token_requests.length
    assert_empty waiter_transport.token_requests
  end

  # Rails wraps each request in a local cache that would answer every poll
  # with the first miss. The fetcher has its own store instance, as in
  # another process.
  def test_a_worker_inside_a_request_local_cache_sees_the_claimed_fetch
    skip "set REDIS_URL to run Redis token store tests" unless redis_url
    namespace = unique_namespace
    fetcher_transport = FakeTransport.new
    waiter_transport = FakeTransport.new
    fetcher = build_client(fetcher_transport, token_store: redis_store(url: redis_url, namespace: namespace))
    assert fetcher.instance_variable_get(:@shared_token_store).claim_fetch(2)
    fetch_once = ->(_seconds) { fetcher.send(:fetch_and_share_token, deadline) if fetcher_transport.token_requests.empty? }
    store = redis_store(url: redis_url, namespace: namespace)
    waiter = build_client(waiter_transport, token_store: store, sleeper: fetch_once)

    store.with_local_cache { register(waiter) }

    assert_equal 1, fetcher_transport.token_requests.length
    assert_empty waiter_transport.token_requests
  ensure
    clear(namespace)
  end

  def test_a_redis_outage_reaches_on_error_when_the_store_re_raises
    transport = FakeTransport.new
    events = []
    sleeps = []
    store = redis_store(url: unreachable_redis_url, error_handler: ->(exception:, **) { raise exception })

    register(build_client(transport, token_store: store, on_error: ->(event) { events << event }, sleeper: sleeps.method(:<<)))

    assert_equal 1, transport.token_requests.length
    assert_empty sleeps
    assert_equal %i[read claim claim write], events.map { |event| event.fetch(:token_store) }
    assert events.all? { |event| event.fetch(:error).is_a?(Redis::BaseConnectionError) }
  end

  # The issuer SDK guide tells Rails users to give the SDK its own re-raising
  # store, because a default Redis cache store turns an outage into a miss. The
  # failed claim must not look like another worker's claim and cause a wait.
  def test_a_redis_outage_is_silent_with_the_default_error_handler
    transport = FakeTransport.new
    events = []
    sleeps = []
    store = redis_store(url: unreachable_redis_url)

    register(build_client(transport, token_store: store, on_error: ->(event) { events << event }, sleeper: sleeps.method(:<<)))

    assert_equal 1, transport.token_requests.length
    assert_empty events
    assert_empty sleeps
  end

  def test_workers_started_after_the_first_reuse_its_stored_token
    skip_without_redis_or_fork
    namespace = unique_namespace

    first = run_workers(1, namespace)
    later = run_workers(3, namespace)

    assert_equal [1], first
    assert_equal [0, 0, 0], later
  ensure
    clear(namespace)
  end

  def test_workers_that_start_together_against_an_empty_store_fetch_once
    skip_without_redis_or_fork
    namespace = unique_namespace

    requests = run_workers(6, namespace)

    assert_equal 1, requests.sum
  ensure
    clear(namespace)
  end

  # The claim lasts the claimant's request budget, so a slow token endpoint
  # does not let the waiting workers fetch their own.
  def test_workers_that_start_together_wait_for_a_slow_fetch
    skip_without_redis_or_fork
    namespace = unique_namespace

    requests = run_workers(64, namespace, token_delay: 3)

    assert_equal 1, requests.sum
  ensure
    clear(namespace)
  end

  def test_a_redis_entry_expires_with_its_token
    skip_without_redis_or_fork
    namespace = unique_namespace

    register(build_client(FakeTransport.new(expires_in: 3600), token_store: redis_store(url: redis_url, namespace: namespace)))

    claims, tokens = redis.keys("#{namespace}:*").partition { |key| key.end_with?(":fetch") }
    assert_equal 1, tokens.length
    assert_includes 3590..3600, redis.ttl(tokens.first)
    assert claims.all? { |key| redis.ttl(key) <= 30 }
  ensure
    clear(namespace)
  end

  private

  def register(client)
    client.register_non_pii(verifiabl_reference: REFERENCE, **registration)
  end

  def redis_store(url:, **options)
    ActiveSupport::Cache::RedisCacheStore.new(url: url, connect_timeout: 0.2, read_timeout: 1, write_timeout: 1, reconnect_attempts: 0, **options)
  end

  # Each worker is a forked process with its own client and store
  # connection, sharing only the Redis server. It reports its token requests.
  def run_workers(count, namespace, token_delay: 0)
    readers = Array.new(count) { fork_worker(namespace, token_delay) }
    Process.waitall
    readers.map do |reader|
      result = reader.read
      reader.close
      Integer(result, exception: false) || flunk("worker failed: #{result}")
    end
  end

  def fork_worker(namespace, token_delay)
    reader, writer = IO.pipe
    fork do
      reader.close
      transport = FakeTransport.new(token_delay: token_delay)
      register(build_client(transport, token_store: redis_store(url: redis_url, namespace: namespace)))
      writer.write(transport.token_requests.length.to_s)
    rescue => error
      writer.write("#{error.class}: #{error.message}")
    ensure
      writer.close
      exit!(0)
    end
    writer.close
    reader
  end

  def skip_without_redis_or_fork
    skip "set REDIS_URL to run Redis token store tests" unless redis_url
    skip "fork is unavailable" unless Process.respond_to?(:fork)
  end

  def redis_url
    url = ENV["REDIS_URL"]
    url unless url.nil? || url.empty?
  end

  def redis
    @redis ||= Redis.new(url: redis_url)
  end

  def unique_namespace
    "verifiabl-issuer-test-#{SecureRandom.hex(6)}"
  end

  def clear(namespace)
    return unless redis_url && namespace

    keys = redis.keys("#{namespace}:*")
    redis.del(*keys) unless keys.empty?
  end

  # A port that was free a moment ago, so connecting to it is refused.
  def unreachable_redis_url
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    server.close
    "redis://127.0.0.1:#{port}/0"
  end
end
