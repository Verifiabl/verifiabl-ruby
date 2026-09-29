# frozen_string_literal: true

require "json"
require_relative "test_helper"

class ClientTest < Minitest::Test
  def test_fetches_and_caches_oauth_token
    requests = []
    transport = lambda do |**request|
      requests << request
      if request.fetch(:url).include?("/oauth/token")
        response(200, access_token: "token-1", expires_in: 3600)
      else
        response(200, verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv")
      end
    end
    client = build_client(transport)

    2.times { client.register_non_pii(verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv", **registration) }

    assert_equal 1, requests.count { |request| request.fetch(:url).include?("/oauth/token") }
    api_requests = requests.reject { |request| request.fetch(:url).include?("/oauth/token") }
    assert api_requests.all? { |request| request.fetch(:headers).fetch("authorization") == "Bearer token-1" }
    assert requests.all? { |request| request.fetch(:headers).fetch("user-agent") == "verifiabl-issuer-ruby/#{Verifiabl::Issuer::VERSION} (ruby #{RUBY_VERSION})" }
  end

  def test_accepts_oauth_bearer_token_type_case_insensitively
    %w[Bearer bearer BEARER].each do |token_type|
      authorization = nil
      transport = lambda do |**request|
        if request.fetch(:url).include?("/oauth/token")
          response(200, access_token: "token", token_type: token_type, expires_in: 3600)
        else
          authorization = request.fetch(:headers).fetch("authorization")
          response(200, verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv")
        end
      end

      build_client(transport).register_non_pii(verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv", **registration)

      assert_equal "Bearer token", authorization
    end
  end

  def test_rejects_non_bearer_oauth_token_types
    %w[Basic DPoP].each do |token_type|
      transport = lambda do |**request|
        if request.fetch(:url).include?("/oauth/token")
          response(200, access_token: "token", token_type: token_type, expires_in: 3600)
        else
          flunk "must not send API request"
        end
      end

      assert_raises(Verifiabl::Issuer::AuthError) do
        build_client(transport).register_non_pii(verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv", **registration)
      end
    end
  end

  def test_rejects_an_invalid_caller_reference_before_sending
    client = build_client(->(**_request) { flunk "must not send" })

    assert_raises(ArgumentError) do
      client.register_non_pii(verifiabl_reference: "bad", **registration)
    end
  end

  def test_sends_a_provider_generated_reference
    bodies = []
    client = build_client(lambda do |**request|
      if request.fetch(:url).include?("/oauth/token")
        response(200, access_token: "token", expires_in: 3600)
      else
        bodies << JSON.parse(request.fetch(:body))
        response(200, verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv")
      end
    end)

    result = client.register_non_pii(verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv", **registration)

    assert_equal "AbCdEfGhIjKlMnOpQrStUv", bodies.first.fetch("verifiabl_reference")
    assert_equal "AbCdEfGhIjKlMnOpQrStUv", result.verifiabl_reference
  end

  def test_mints_reference_before_registration_for_idempotency
    bodies = []
    client = build_client(lambda do |**request|
      if request.fetch(:url).include?("/oauth/token")
        response(200, access_token: "token", expires_in: 3600)
      else
        bodies << JSON.parse(request.fetch(:body))
        response(200, verifiabl_reference: bodies.first.fetch("verifiabl_reference"))
      end
    end)

    result = client.register_non_pii(**registration)

    assert_match(/\A[A-Za-z0-9_-]{22}\z/, bodies.first.fetch("verifiabl_reference"))
    assert_equal bodies.first.fetch("verifiabl_reference"), result.verifiabl_reference
  end

  def test_reuses_generated_reference_across_automatic_retries
    bodies = []
    client = build_client(lambda do |**request|
      if request.fetch(:url).include?("/oauth/token")
        response(200, access_token: "token", expires_in: 3600)
      else
        bodies << JSON.parse(request.fetch(:body))
        if bodies.length == 1
          response(503, code: "SERVICE_UNAVAILABLE")
        else
          response(200, verifiabl_reference: bodies.first.fetch("verifiabl_reference"))
        end
      end
    end, sleeper: ->(_seconds) {})

    result = client.register_non_pii(**registration)

    assert_equal 2, bodies.length
    assert_equal bodies.first.fetch("verifiabl_reference"), bodies.last.fetch("verifiabl_reference")
    assert_equal bodies.first.fetch("verifiabl_reference"), result.verifiabl_reference
  end

  def test_raises_conflict_for_reference_reused_with_different_content
    client = build_client(lambda do |**request|
      if request.fetch(:url).include?("/oauth/token")
        response(200, access_token: "token", expires_in: 3600)
      else
        response(409, error: "reference already belongs to different content", code: "CONFLICT")
      end
    end)

    error = assert_raises(Verifiabl::Issuer::ApiError) do
      client.register_non_pii(verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv", **registration)
    end
    assert_equal 409, error.status
    assert_equal "CONFLICT", error.code
  end

  def test_raises_typed_api_errors_without_exposing_request_bodies
    client = build_client(lambda do |**request|
      if request.fetch(:url).include?("/oauth/token")
        response(200, access_token: "token", expires_in: 3600)
      else
        Verifiabl::Issuer::Client::Response.new(
          status: 409,
          headers: {"request-id" => "request-1"},
          body: JSON.generate(code: "IV_REUSED", error: "already used")
        )
      end
    end)

    error = assert_raises(Verifiabl::Issuer::IvReuseError) { client.register_non_pii(**registration) }
    assert_equal 409, error.status
    assert_equal "IV_REUSED", error.code
    assert_equal "request-1", error.request_id
    assert_equal "The encryption IV is already registered. Encrypt the payslip again and rebuild its barcode.", error.message
    refute_includes error.message, "Jane"
  end

  def test_normalizes_malformed_api_error_bodies
    [{"code" => nil, "error" => "bad gateway"}, [], {"code" => "BAD_GATEWAY", "error" => nil}].each do |body|
      client = build_client(lambda do |**request|
        request.fetch(:url).include?("/oauth/token") ? response(200, access_token: "token", expires_in: 3600) : Verifiabl::Issuer::Client::Response.new(status: 502, headers: {}, body: JSON.generate(body))
      end)

      error = assert_raises(Verifiabl::Issuer::ApiError) { client.register_non_pii(**registration) }
      assert_equal "INTERNAL_ERROR", error.code
      assert_nil error.body
    end
  end

  def test_raises_auth_error_when_the_token_endpoint_cannot_be_reached
    client = build_client(->(**_request) { raise IOError, "socket closed" }, max_retries: 0)

    error = assert_raises(Verifiabl::Issuer::AuthError) { client.register_non_pii(**registration) }
    assert_nil error.status
    assert_match("OAuth token endpoint", error.message)
  end

  def test_refreshes_a_rejected_token_exactly_once
    tokens = %w[token-1 token-2]
    authorizations = []
    transport = lambda do |**request|
      if request.fetch(:url).include?("/oauth/token")
        response(200, access_token: tokens.shift, expires_in: 3600)
      else
        authorizations << request.fetch(:headers).fetch("authorization")
        (authorizations.length == 1) ? response(401, code: "UNAUTHORIZED") : response(200, verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv")
      end
    end

    build_client(transport).register_non_pii(verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv", **registration)

    assert_equal ["Bearer token-1", "Bearer token-2"], authorizations
  end

  def test_retries_idempotent_registration_and_honours_retry_after
    sleeps = []
    api_calls = 0
    transport = lambda do |**request|
      if request.fetch(:url).include?("/oauth/token")
        response(200, access_token: "token", expires_in: 3600)
      else
        api_calls += 1
        (api_calls == 1) ? Verifiabl::Issuer::Client::Response.new(status: 503, headers: {"retry-after" => "2"}, body: "") : response(200, verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv")
      end
    end
    client = build_client(transport, sleeper: ->(seconds) { sleeps << seconds })

    client.register_non_pii(verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv", **registration)

    assert_equal 2, api_calls
    assert_equal [2], sleeps
  end

  def test_does_not_retry_non_idempotent_registration_after_server_error
    api_calls = 0
    transport = lambda do |**request|
      if request.fetch(:url).include?("/oauth/token")
        response(200, access_token: "token", expires_in: 3600)
      else
        api_calls += 1
        response(503, code: "UNAVAILABLE")
      end
    end
    client = build_client(transport, sleeper: ->(_seconds) { flunk "must not sleep" })

    assert_raises(Verifiabl::Issuer::ApiError) do
      client.register_and_build_barcode(encrypted_pii: "foo".b, **registration)
    end
    assert_equal 1, api_calls
  end

  def test_retries_rate_limits_for_non_idempotent_registration
    api_calls = 0
    client = build_client(lambda do |**request|
      if request.fetch(:url).include?("/oauth/token")
        response(200, access_token: "token", expires_in: 3600)
      else
        api_calls += 1
        (api_calls == 1) ? response(429, code: "RATE_LIMITED") : response(200, verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv", barcode: {format: "png", data: "cG5n"})
      end
    end, sleeper: ->(_seconds) {})

    client.register_and_build_barcode(encrypted_pii: "foo".b, **registration)
    assert_equal 2, api_calls
  end

  def test_sends_json_oauth_contract_with_audience
    token_body = nil
    transport = lambda do |**request|
      if request.fetch(:url).include?("/oauth/token")
        token_body = JSON.parse(request.fetch(:body))
        response(200, access_token: "token", expires_in: 3600)
      else
        response(200, verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv")
      end
    end

    build_client(transport).register_non_pii(verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv", **registration)

    assert_equal "client_credentials", token_body.fetch("grant_type")
    assert_equal "client", token_body.fetch("client_id")
    assert_equal "secret", token_body.fetch("client_secret")
    assert_equal "https://register.sandbox.verifiabl.io", token_body.fetch("audience")
    assert_equal "verifiabl:issuer", token_body.fetch("scope")
  end

  def test_accepts_custom_transport
    configuration = Verifiabl::Issuer::Configuration.new
    transport = ->(**) {}

    client = Verifiabl::Issuer::Client.new(configuration, transport: transport)

    assert_same transport, client.instance_variable_get(:@transport)
  end

  def test_rejects_internal_runtime_dependency_keywords
    configuration = Verifiabl::Issuer::Configuration.new

    assert_raises(ArgumentError) { Verifiabl::Issuer::Client.new(configuration, clock: -> { Time.now }) }
  end

  def test_rejects_non_callable_transport
    configuration = Verifiabl::Issuer::Configuration.new

    error = assert_raises(ArgumentError) { Verifiabl::Issuer::Client.new(configuration, transport: Object.new) }

    assert_equal "transport must respond to call", error.message
  end

  def test_rejects_unsafe_endpoint_overrides
    configuration = Verifiabl::Issuer::Configuration.new(token_url: "https://attacker.example/token")
    assert_raises(ArgumentError) { Verifiabl::Issuer::Client.new(configuration) }

    configuration = Verifiabl::Issuer::Configuration.new(issuer_base_url: "http://api.example")
    assert_raises(ArgumentError) { Verifiabl::Issuer::Client.new(configuration) }
  end

  def test_accepts_bracketed_ipv6_loopback_endpoint_overrides
    [
      ["http://[::1]:3000", "http://[::1]:4000/oauth/token"],
      ["https://[::1]:3443", "https://[::1]:4443/oauth/token"]
    ].each do |issuer_base_url, token_url|
      requests = []
      transport = lambda do |**request|
        requests << request
        if request.fetch(:url) == token_url
          response(200, access_token: "token", expires_in: 3600)
        else
          response(200, verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv")
        end
      end
      client = build_client(transport, issuer_base_url: issuer_base_url, token_url: token_url)

      client.register_non_pii(verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv", **registration)

      assert_equal token_url, requests.fetch(0).fetch(:url)
      assert_equal issuer_base_url, JSON.parse(requests.fetch(0).fetch(:body)).fetch("audience")
      assert_equal "#{issuer_base_url}/v1/registerNonPII", requests.fetch(1).fetch(:url)
    end
  end

  def test_retries_transport_faults_for_idempotent_calls
    api_calls = 0
    client = build_client(lambda do |**request|
      if request.fetch(:url).include?("/oauth/token")
        response(200, access_token: "token", expires_in: 3600)
      else
        api_calls += 1
        raise Errno::ECONNRESET if api_calls == 1
        response(200, verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv")
      end
    end, sleeper: ->(_seconds) {})

    client.register_non_pii(verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv", **registration)
    assert_equal 2, api_calls
  end

  def test_honours_http_date_retry_after
    now = Time.utc(2026, 6, 11)
    sleeps = []
    api_calls = 0
    client = build_client(lambda do |**request|
      if request.fetch(:url).include?("/oauth/token")
        response(200, access_token: "token", expires_in: 3600)
      else
        api_calls += 1
        if api_calls == 1
          Verifiabl::Issuer::Client::Response.new(status: 503, headers: {"retry-after" => (now + 3).httpdate}, body: "")
        else
          response(200, verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv")
        end
      end
    end, clock: -> { now }, sleeper: ->(seconds) { sleeps << seconds })

    client.register_non_pii(verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv", **registration)
    assert_equal [3], sleeps
  end

  def test_deadline_exhaustion_stops_before_retry
    elapsed = 0.0
    client = build_client(lambda do |**request|
      if request.fetch(:url).include?("/oauth/token")
        response(200, access_token: "token", expires_in: 3600)
      else
        response(503, code: "UNAVAILABLE")
      end
    end, timeout: 0.2, monotonic_clock: -> { elapsed }, sleeper: ->(seconds) { elapsed += seconds })

    assert_raises(Verifiabl::Issuer::TimeoutError) do
      client.register_non_pii(verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv", **registration)
    end
  end

  def test_transport_receives_remaining_budget_without_async_timeout
    elapsed = 0.0
    budgets = []
    client = build_client(lambda do |**request|
      budgets << request.fetch(:timeout)
      elapsed += 2
      if request.fetch(:url).include?("/oauth/token")
        response(200, access_token: "token", expires_in: 3600)
      else
        response(200, verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv")
      end
    end, timeout: 10, monotonic_clock: -> { elapsed })

    trace = TracePoint.new(:call) do |event|
      flunk "must not asynchronously interrupt transport" if event.self == Timeout && event.method_id == :timeout
    end
    trace.enable do
      client.register_non_pii(verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv", **registration)
    end
    assert_equal [10, 8], budgets
  end

  def test_rejects_response_arriving_after_deadline
    elapsed = 0.0
    calls = 0
    client = build_client(lambda do |**request|
      calls += 1
      if request.fetch(:url).include?("/oauth/token")
        response(200, access_token: "token", expires_in: 3600)
      else
        elapsed = 11
        response(200, verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv")
      end
    end, timeout: 10, monotonic_clock: -> { elapsed })

    assert_raises(Verifiabl::Issuer::TimeoutError) { client.register_non_pii(**registration) }
    assert_equal 2, calls
  end

  def test_native_io_timeouts_are_mapped_without_retry
    [Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout].each do |error_class|
      [true, false].each do |during_auth|
        calls = 0
        client = build_client(lambda do |**request|
          calls += 1
          raise error_class if during_auth || !request.fetch(:url).include?("/oauth/token")
          response(200, access_token: "token", expires_in: 3600)
        end)

        assert_raises(Verifiabl::Issuer::TimeoutError) { client.register_non_pii(**registration) }
        assert_equal(during_auth ? 1 : 2, calls)
      end
    end
  end

  def test_token_refresh_and_invalidation_lock_waits_observe_caller_deadline
    [:access_token, :invalidate_token].each do |operation|
      elapsed = 0.0
      client = build_client(->(**) { flunk "must not request while waiting for token lock" },
        timeout: 0.05, monotonic_clock: -> { elapsed }, sleeper: ->(seconds) { elapsed += seconds })
      mutex = client.instance_variable_get(:@token_mutex)
      mutex.lock
      begin
        assert_raises(Verifiabl::Issuer::TimeoutError) do
          if operation == :access_token
            client.send(:access_token, 0.05)
          else
            client.send(:invalidate_token, "token", 0.05)
          end
        end
        assert_operator elapsed, :>=, 0.05
      ensure
        mutex.unlock
      end
      refute mutex.locked?
    end
  end

  def test_concurrent_calls_single_flight_token_refresh
    mutex = Mutex.new
    ready = ConditionVariable.new
    token_fetches = 0
    rejected_calls = 0
    transport = lambda do |**request|
      if request.fetch(:url).include?("/oauth/token")
        number = mutex.synchronize { token_fetches += 1 }
        response(200, access_token: "token-#{number}", expires_in: 3600)
      else
        authorization = request.fetch(:headers).fetch("authorization")
        if authorization == "Bearer token-1"
          mutex.synchronize do
            rejected_calls += 1
            ready.broadcast if rejected_calls == 8
            ready.wait(mutex) while rejected_calls < 8
          end
          response(401, code: "UNAUTHORIZED")
        else
          response(200, verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv")
        end
      end
    end
    client = build_client(transport)

    threads = 8.times.map do
      Thread.new { client.register_non_pii(verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv", **registration) }
    end
    threads.each(&:value)

    assert_equal 2, token_fetches
    assert_equal 8, rejected_calls
  end

  def test_rejects_malformed_success_response
    client = build_client(lambda do |**request|
      request.fetch(:url).include?("/oauth/token") ? response(200, access_token: "token", expires_in: 3600) : response(200, status: "created")
    end)

    assert_raises(Verifiabl::Issuer::TransportError) { client.register_non_pii(**registration) }
  end

  def test_maps_and_validates_batch_results
    record = registration.merge(verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv", external_id: "pay-1")
    client = build_client(lambda do |**request|
      if request.fetch(:url).include?("/oauth/token")
        response(200, access_token: "token", expires_in: 3600)
      else
        response(200, results: [{status: "created", verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv", external_id: "pay-1"}])
      end
    end)

    result = client.register_non_pii_batch([record])

    assert_instance_of Verifiabl::Issuer::Responses::BatchRegistration, result
    assert_equal "created", result.results.first.status
    assert_equal "pay-1", result.results.first.external_id
  end

  def test_legacy_new_zealand_v1_batch_record_is_sent
    requests = []
    reference = "AbCdEfGhIjKlMnOpQrStUv"
    record = registration.merge(schema: "nz.payslip.v1", verifiabl_reference: reference)
    client = build_client(lambda do |**request|
      requests << request
      if request.fetch(:url).include?("/oauth/token")
        response(200, access_token: "token", expires_in: 3600)
      else
        response(200, results: [{status: "created", verifiabl_reference: reference}])
      end
    end)

    result = client.register_non_pii_batch([record])

    assert_equal "nz.payslip.v1", JSON.parse(requests.last.fetch(:body)).fetch("records").first.fetch("schema")
    assert_equal "created", result.results.first.status
  end

  def test_invalid_v2_batch_record_is_not_sent_and_keeps_result_order
    requests = []
    good_reference = "Xk2mP9qRsT4uVwYzAbCdEf"
    bad = registration.merge(schema: "au.payslip.v2", verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv", external_id: "bad-1",
      payslip_non_pii: {period_end: "2026-06-15", currency: "AUD", gross: {employee_name: "Jane"}})
    good = registration.merge(verifiabl_reference: good_reference)
    client = build_client(lambda do |**request|
      requests << request
      if request.fetch(:url).include?("/oauth/token")
        response(200, access_token: "token", expires_in: 3600)
      else
        response(200, results: [{status: "created", verifiabl_reference: good_reference}])
      end
    end)

    result = client.register_non_pii_batch([bad, good])

    wire = JSON.parse(requests.last.fetch(:body))
    assert_equal good_reference, wire.fetch("records").fetch(0).fetch("verifiabl_reference")
    assert_equal 1, wire.fetch("records").length
    assert_equal "VALIDATION_FAILED", result.results.fetch(0).code
    assert_equal "bad-1", result.results.fetch(0).external_id
    assert_equal "created", result.results.fetch(1).status
  end

  def test_all_invalid_v2_batch_records_do_not_fetch_a_token
    calls = []
    invalid = registration.merge(schema: "au.payslip.v2", verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv",
      payslip_non_pii: {employee_name: "Jane"})
    client = build_client(lambda do |**request|
      calls << request
      raise "unexpected network request"
    end)

    result = client.register_non_pii_batch([invalid])

    assert_empty calls
    assert_equal "VALIDATION_FAILED", result.results.fetch(0).code
  end

  def test_rejects_batch_result_count_mismatch
    record = registration.merge(verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv")
    client = build_client(lambda do |**request|
      request.fetch(:url).include?("/oauth/token") ? response(200, access_token: "token", expires_in: 3600) : response(200, results: [])
    end)

    assert_raises(Verifiabl::Issuer::TransportError) { client.register_non_pii_batch([record]) }
  end

  def test_emits_request_and_response_hooks_without_bodies
    requests = []
    responses = []
    transport = lambda do |**request|
      if request.fetch(:url).include?("/oauth/token")
        response(200, access_token: "token", expires_in: 3600)
      else
        Verifiabl::Issuer::Client::Response.new(
          status: 200,
          headers: {"x-verifiabl-request-id" => "req_hook"},
          body: JSON.generate(verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv")
        )
      end
    end
    client = build_client(transport, on_request: requests.method(:<<), on_response: responses.method(:<<))

    client.register_non_pii(verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv", **registration)

    assert_equal({method: "POST", url: "https://register.sandbox.verifiabl.io/v1/registerNonPII", path: "/v1/registerNonPII"}, requests.fetch(0))
    assert_equal 200, responses.fetch(0).fetch(:status)
    assert_equal "req_hook", responses.fetch(0).fetch(:request_id)
    assert_operator responses.fetch(0).fetch(:elapsed_ms), :>=, 0
    refute requests.fetch(0).key?(:body)
    refute responses.fetch(0).key?(:body)
  end

  def test_emits_error_hooks_for_transport_failures
    errors = []
    transport = lambda do |**request|
      request.fetch(:url).include?("/oauth/token") ? response(200, access_token: "token", expires_in: 3600) : raise(IOError, "socket closed")
    end
    client = build_client(transport, max_retries: 0, on_error: errors.method(:<<))

    assert_raises(Verifiabl::Issuer::TransportError) do
      client.register_non_pii(verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv", **registration)
    end

    assert_equal "/v1/registerNonPII", errors.fetch(0).fetch(:path)
    assert_instance_of Verifiabl::Issuer::TransportError, errors.fetch(0).fetch(:error)
    refute errors.fetch(0).key?(:body)
  end

  def test_observability_hook_failures_do_not_change_request_behaviour
    failing_hook = ->(_event) { raise "hook failed" }
    transport = lambda do |**request|
      request.fetch(:url).include?("/oauth/token") ? response(200, access_token: "token", expires_in: 3600) : response(200, verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv")
    end
    client = build_client(transport, on_request: failing_hook, on_response: failing_hook)

    result = client.register_non_pii(verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv", **registration)

    assert_equal "AbCdEfGhIjKlMnOpQrStUv", result.verifiabl_reference
  end

  private

  def build_client(transport, **options)
    runtime_keys = %i[clock sleeper random monotonic_clock]
    runtime_options = options.slice(*runtime_keys)
    configuration = Verifiabl::Issuer::Configuration.new(
      client_id: "client",
      client_secret: "secret",
      environment: :sandbox,
      **options.except(*runtime_keys)
    )
    client = Verifiabl::Issuer::Client.new(configuration, transport: transport)
    client.send(:configure_runtime_dependencies, transport: transport, **runtime_options) unless runtime_options.empty?
    client
  end

  def response(status, body)
    body = body.merge(token_type: "Bearer") if body.key?(:access_token) && !body.key?(:token_type)
    Verifiabl::Issuer::Client::Response.new(status: status, headers: {}, body: JSON.generate(body))
  end

  def registration
    {
      schema: "au.payslip.v1",
      issued_at: "2026-06-11T00:00:00Z",
      payslip_non_pii: {period_start: "2026-06-01", employee_label: "Jane"},
      encryption_metadata: {iv: "\0".b * 12, tag: "\0".b * 16}
    }
  end
end
