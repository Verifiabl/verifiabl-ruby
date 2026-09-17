# frozen_string_literal: true

require "ipaddr"
require "json"
require "net/http"
require "time"
require "timeout"
require "uri"

module Verifiabl
  module Issuer
    class Client
      Response = Data.define(:status, :headers, :body)
      CachedToken = Data.define(:value, :issued_at, :expires_at)
      ISSUER_SCOPE = "verifiabl:issuer"
      VERIFIABL_AUTH_HOSTS = %w[auth.verifiabl.io auth.sandbox.verifiabl.io].freeze
      RETRY_BASE_SECONDS = 0.5
      RETRY_MAX_SECONDS = 8.0
      REQUEST_ID_HEADERS = %w[x-request-id request-id x-verifiabl-request-id].freeze

      def self.request_id(headers)
        REQUEST_ID_HEADERS.each do |name|
          value = headers[name] || headers.find { |key, _| key.casecmp?(name) }&.last
          return value if value.is_a?(String) && !value.empty?
        end
        nil
      end

      def initialize(configuration, **runtime_dependencies)
        configure_endpoints(configuration)
        configure_retry_policy(configuration)
        configure_runtime_dependencies(**runtime_dependencies)
        @on_request = configuration.on_request
        @on_response = configuration.on_response
        @on_error = configuration.on_error
        @token_mutex = Mutex.new
        @process_id = Process.pid
      end

      # Registers non-PII data under a provider-generated reference. When the
      # caller omits one, generate it once before the request loop so every
      # automatic retry uses the same idempotency key. Callers that need to
      # retry from another process or invocation should generate, persist, and
      # pass the reference explicitly.
      def register_non_pii(verifiabl_reference: nil, **registration)
        reference = verifiabl_reference || Payload.generate_reference
        Validation.reference!(reference)
        body = Serialization.registration_to_wire(**registration).merge("verifiabl_reference" => reference)
        parsed = post("/v1/registerNonPII", body, idempotent: true)
        Responses.registration(parsed, expected_reference: reference)
      end

      def register_non_pii_batch(records)
        body = Serialization.batch_to_wire(records: records)
        parsed = post("/v1/registerNonPIIBatch", body, idempotent: true)
        Responses.batch_registration(parsed, expected_records: records)
      end

      def register_and_build_barcode(encrypted_pii:, **registration)
        body = Serialization.register_and_build_barcode_to_wire(encrypted_pii: encrypted_pii, **registration)
        Responses.barcode_registration(post("/v1/registerAndBuildBarcode", body, idempotent: false))
      end

      private

      def post(path, body, idempotent:)
        deadline = @monotonic_clock.call + @timeout
        Timeout.timeout(@timeout) { perform_post(path, JSON.generate(body), deadline, idempotent) }
      rescue Timeout::Error
        raise TimeoutError, @timeout
      end

      def perform_post(path, json, deadline, idempotent)
        attempt = 0
        loop do
          ensure_before_deadline!(deadline)
          response = send_with_auth(path, json, deadline)
          return parse_response(response) unless retry_response?(response, attempt, idempotent)

          attempt += 1
          sleep_before_retry(retry_delay(response, attempt), deadline)
        rescue TransportError
          raise unless retry_transport?(attempt, deadline, idempotent)

          attempt += 1
          sleep_before_retry(backoff(attempt), deadline)
        end
      end

      def retry_response?(response, attempt, idempotent)
        attempt < @max_retries && retryable_status?(response.status, idempotent)
      end

      def retry_transport?(attempt, deadline, idempotent)
        idempotent && attempt < @max_retries && !deadline_expired?(deadline)
      end

      def send_with_auth(path, body, deadline)
        token = access_token(deadline)
        response = issuer_request(path, body, token, deadline)
        return response unless response.status == 401

        invalidate_token(token)
        issuer_request(path, body, access_token(deadline), deadline)
      end

      def issuer_request(path, body, token, deadline)
        url = @issuer_base_url + path
        Instrumentation.observe_request(
          {method: "POST", url: url, path: path},
          on_request: @on_request,
          on_response: @on_response,
          on_error: @on_error,
          monotonic_clock: @monotonic_clock
        ) do
          request(
            method: :post,
            url: url,
            headers: json_headers.merge("authorization" => "Bearer #{token}"),
            body: body,
            deadline: deadline
          )
        end
      end

      def parse_response(response)
        parsed = parse_json(response.body)
        if response.status.between?(200, 299)
          raise TransportError, "Verifiabl API returned an invalid JSON response" unless parsed.is_a?(Hash)
          return parsed
        end

        error_class = (ApiError.valid_body?(parsed) && parsed["code"] == "IV_REUSED") ? IvReuseError : ApiError
        raise error_class.new(status: response.status, body: parsed, request_id: self.class.request_id(response.headers))
      end

      def json_headers
        {"content-type" => "application/json", "accept" => "application/json", "user-agent" => "verifiabl-ruby/#{VERSION}"}
      end

      def access_token(deadline)
        reset_token_cache_after_fork!
        now = @clock.call
        cached = @token
        return cached.value if cached && token_fresh?(cached, now)

        ensure_before_deadline!(deadline)
        @token_mutex.synchronize do
          ensure_before_deadline!(deadline)
          now = @clock.call
          return @token.value if @token && token_fresh?(@token, now)

          @token = fetch_token(now, deadline)
          @token.value
        end
      end

      def invalidate_token(rejected)
        reset_token_cache_after_fork!
        @token_mutex.synchronize { @token = nil if @token&.value == rejected }
      end

      # Forking while another thread refreshes a token leaves the child with a
      # permanently locked copy of the parent's mutex. A child has one thread
      # immediately after fork, so replacing this local state before locking is
      # safe and gives it an independent token cache.
      def reset_token_cache_after_fork!
        return if @process_id == Process.pid

        @token_mutex = Mutex.new
        @token = nil
        @process_id = Process.pid
      end

      def token_fresh?(token, now)
        ttl = token.expires_at - token.issued_at
        token.expires_at - now > [60, ttl / 2].min
      end

      def fetch_token(now, deadline)
        validate_credentials!
        response = request(method: :post, url: @token_url, headers: json_headers, body: token_request_body, deadline: deadline)
        parsed = parse_json(response.body)
        validate_token_response!(response, parsed)
        CachedToken.new(value: parsed["access_token"], issued_at: now, expires_at: now + parsed["expires_in"])
      rescue TimeoutError
        raise
      rescue TransportError => error
        raise AuthError, "Could not reach the Verifiabl OAuth token endpoint: #{error.message}"
      end

      def validate_credentials!
        valid_id = @client_id.is_a?(String) && !@client_id.strip.empty?
        valid_secret = @client_secret.is_a?(String) && !@client_secret.strip.empty?
        raise AuthError, "client_id and client_secret are required" unless valid_id && valid_secret
      end

      def token_request_body
        JSON.generate(
          grant_type: "client_credentials",
          client_id: @client_id.strip,
          client_secret: @client_secret.strip,
          audience: @issuer_base_url,
          scope: ISSUER_SCOPE
        )
      end

      def validate_token_response!(response, parsed)
        raise AuthError.new("OAuth token request failed", status: response.status) unless response.status.between?(200, 299)

        valid = parsed.is_a?(Hash) && valid_access_token?(parsed) && valid_token_expiry?(parsed["expires_in"])
        raise AuthError.new("OAuth token response is invalid", status: response.status) unless valid
      end

      def valid_access_token?(parsed)
        parsed["access_token"].is_a?(String) && !parsed["access_token"].empty? && parsed["token_type"] == "Bearer"
      end

      def valid_token_expiry?(value)
        value.is_a?(Numeric) && value.finite? && value.positive?
      end

      def retryable_status?(status, idempotent)
        status == 429 || (idempotent && (status == 408 || status.between?(500, 599)))
      end

      def retry_delay(response, attempt)
        value = response.headers["retry-after"]
        return backoff(attempt) unless value

        seconds = Integer(value, exception: false)
        return [seconds, 0].max if seconds

        date = Time.httpdate(value)
        [date - @clock.call, 0].max
      rescue ArgumentError
        backoff(attempt)
      end

      def backoff(attempt)
        capped = [RETRY_MAX_SECONDS, RETRY_BASE_SECONDS * (2**(attempt - 1))].min
        (capped / 2) + ((capped / 2) * @random.rand)
      end

      def sleep_before_retry(seconds, deadline)
        remaining = remaining_time(deadline)
        raise TimeoutError, @timeout if seconds >= remaining
        @sleeper.call(seconds)
        ensure_before_deadline!(deadline)
      end

      def request(deadline:, **options)
        remaining = remaining_time(deadline)
        raise TimeoutError, @timeout unless remaining.positive?
        Timeout.timeout(remaining) { @transport.call(**options.merge(timeout: remaining)) }
      rescue AuthError, ApiError, TransportError
        raise
      rescue Timeout::Error
        raise TimeoutError, @timeout
      rescue SystemCallError, IOError, SocketError => error
        raise TransportError, "Verifiabl request failed: #{error.message}"
      end

      def parse_json(value)
        JSON.parse(value)
      rescue JSON::ParserError
        nil
      end

      def remaining_time(deadline)
        deadline - @monotonic_clock.call
      end

      def deadline_expired?(deadline)
        remaining_time(deadline) <= 0
      end

      def ensure_before_deadline!(deadline)
        raise TimeoutError, @timeout if deadline_expired?(deadline)
      end

      def configure_endpoints(configuration)
        @client_id = configuration.client_id
        @client_secret = configuration.client_secret
        origins = Payload.resolve_environment(configuration.environment)
        @token_url = normalize_token_url(configuration.token_url || origins.fetch(:token_url))
        @issuer_base_url = normalize_issuer_base_url(configuration.issuer_base_url || origins.fetch(:issuer_base_url))
      end

      def configure_retry_policy(configuration)
        @timeout = configuration.timeout
        @max_retries = configuration.max_retries
        raise ArgumentError, "timeout must be positive" unless @timeout.is_a?(Numeric) && @timeout.finite? && @timeout.positive?
        raise ArgumentError, "max_retries must be a non-negative integer" unless @max_retries.is_a?(Integer) && @max_retries >= 0
      end

      def configure_runtime_dependencies(transport: nil, clock: nil, sleeper: nil, random: nil, monotonic_clock: nil)
        @transport = transport || method(:net_http_request)
        @clock = clock || -> { Time.now }
        @monotonic_clock = monotonic_clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        @sleeper = sleeper || ->(seconds) { sleep(seconds) }
        @random = random || Random.new
      end

      def normalize_issuer_base_url(value)
        uri = parse_absolute_url(value, "issuer_base_url")
        secure = uri.scheme == "https"
        local = uri.scheme == "http" && loopback_host?(uri.hostname)
        raise ArgumentError, "issuer_base_url must use https, except for loopback development URLs" unless secure || local
        normalized_origin(uri)
      end

      def normalize_token_url(value)
        uri = parse_absolute_url(value, "token_url", allow_path: true)
        allowed_verifiabl = uri.scheme == "https" && VERIFIABL_AUTH_HOSTS.include?(uri.host.downcase)
        allowed_loopback = %w[http https].include?(uri.scheme) && loopback_host?(uri.hostname)
        raise ArgumentError, "token_url must use a Verifiabl auth host, or loopback for development" unless allowed_verifiabl || allowed_loopback
        uri.to_s
      end

      def parse_absolute_url(value, name, allow_path: false)
        raise ArgumentError, "#{name} must be a URL" unless value.is_a?(String)

        uri = URI.parse(value)
        requirement = allow_path ? "an absolute URL" : "an absolute origin without a path"
        raise ArgumentError, "#{name} must be #{requirement}" if invalid_absolute_url?(uri, allow_path)
        uri
      rescue URI::InvalidURIError
        raise ArgumentError, "#{name} is invalid"
      end

      def invalid_absolute_url?(uri, allow_path)
        invalid_path = !allow_path && !["", "/"].include?(uri.path)
        !uri.absolute? || uri.host.nil? || uri.userinfo || uri.query || uri.fragment || invalid_path
      end

      def normalized_origin(uri)
        port = (uri.port == uri.default_port) ? "" : ":#{uri.port}"
        hostname = uri.hostname
        host = hostname.include?(":") ? "[#{hostname}]" : hostname
        "#{uri.scheme}://#{host}#{port}"
      end

      def loopback_host?(host)
        return true if host.casecmp("localhost").zero?
        IPAddr.new(host).loopback?
      rescue IPAddr::InvalidAddressError
        false
      end

      def net_http_request(method:, url:, headers:, body:, timeout:)
        uri = URI.parse(url)
        http_request = Net::HTTP::Post.new(uri)
        headers.each { |key, value| http_request[key] = value }
        http_request.body = body
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: timeout, read_timeout: timeout, write_timeout: timeout) { |http| http.request(http_request) }
        Response.new(status: response.code.to_i, headers: response.each_header.to_h, body: response.body.to_s)
      end
    end
  end
end
