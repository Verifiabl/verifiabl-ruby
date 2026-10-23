# frozen_string_literal: true

require "json"
require "openssl"
require "securerandom"

module Verifiabl
  module Issuer
    # Keeps OAuth tokens in an application cache that several processes
    # share, such as a Redis-backed cache, so a fleet of job workers reuses
    # one token instead of each worker fetching its own.
    #
    # The backend sees only an opaque key and AES-256-GCM ciphertext. Both
    # are derived from the client secret and the token's identity (token
    # URL, client ID, audience and scope): reading the cache without the
    # secret reveals no token, and the secret alone can already mint one.
    #
    # Backend failures and unreadable entries count as a miss and are
    # reported through `on_error`, so a cache outage costs a token fetch
    # rather than blocking registration.
    #
    # @api private
    class SharedTokenStore
      FORMAT = "v1"
      KEY_PREFIX = "verifiabl-issuer:token:#{FORMAT}:"
      VALUE_PREFIX = "#{FORMAT}:"
      KEY_BYTES = 32
      IV_BYTES = 12
      TAG_BYTES = 16
      BACKEND_METHODS = %i[read write].freeze
      FETCH_CLAIM_SUFFIX = ":fetch"

      def self.valid_backend?(backend)
        BACKEND_METHODS.all? { |name| backend.respond_to?(name) }
      end

      # @param identity [Array] everything besides the secret that selects a
      #   token: token URL, client ID, audience and scope.
      # @param on_error [#call, nil] receives `{token_store:, error:}` when
      #   the backend raises; the failure never changes request behaviour.
      def initialize(backend, client_secret:, identity:, on_error: nil)
        @backend = backend
        @on_error = on_error
        identity_json = JSON.generate(identity)
        @encryption_key = derive_key(client_secret, "encryption", identity_json)
        lookup_key = derive_key(client_secret, "lookup", identity_json)
        @key = KEY_PREFIX + OpenSSL::HMAC.hexdigest("SHA256", lookup_key, identity_json)
        @fetch_claim_key = @key + FETCH_CLAIM_SUFFIX
      end

      # Returns the stored token, or nil when there is none that is unexpired.
      def read(now)
        observe(:read) { decode(read_backend(@key), now) }
      end

      def write(token, now)
        seconds_left = (token.expires_at - now).floor
        return unless seconds_left.positive?

        observe(:write) { @backend.write(@key, encode(token), expires_in: seconds_left) }
      end

      # Claims the next token fetch for `seconds`. Returns `false` only when a
      # claim exists. The claim expires instead of being deleted, so it never
      # removes a later process's claim.
      def claim_fetch(seconds)
        observe(:claim) { @backend.write(@fetch_claim_key, "1", expires_in: seconds, unless_exist: true) }
      end

      # True while a process holds the claim. A store that swallows a backend
      # error answers `nil`, so an outage never makes a process wait.
      def fetch_claim_held?
        observe(:claim) { read_backend(@fetch_claim_key) } == "1"
      end

      private

      # In a Rails request, Active Support stores answer repeat reads from a
      # request-local cache, so a poll would see only its first miss. A fresh
      # local cache for each read sends it to the backend.
      def read_backend(key)
        return @backend.read(key) unless @backend.respond_to?(:with_local_cache)

        @backend.with_local_cache { @backend.read(key) }
      end

      # The backend is the application's cache, so its failures and any
      # unreadable entry count as a miss. The report lets an operator see a
      # store that is misconfigured or down, which would otherwise look like
      # the store doing nothing.
      def observe(operation)
        yield
      rescue => error
        Instrumentation.emit_error({token_store: operation, error: error}, @on_error)
        nil
      end

      def derive_key(secret, purpose, identity_json)
        OpenSSL::KDF.hkdf(
          secret,
          salt: "",
          info: "verifiabl-issuer token store #{FORMAT} #{purpose} #{identity_json}",
          length: KEY_BYTES,
          hash: "SHA256"
        )
      end

      def encode(token)
        payload = JSON.generate(
          "access_token" => token.value,
          "issued_at" => token.issued_at.to_f,
          "expires_at" => token.expires_at.to_f
        )
        iv = SecureRandom.random_bytes(IV_BYTES)
        cipher = start_cipher(:encrypt, iv)
        ciphertext = cipher.update(payload) + cipher.final
        VALUE_PREFIX + [iv + ciphertext + cipher.auth_tag].pack("m0")
      end

      def decode(value, now)
        return unless value.is_a?(String) && value.start_with?(VALUE_PREFIX)

        bytes = value.delete_prefix(VALUE_PREFIX).unpack1("m0")
        return if bytes.bytesize <= IV_BYTES + TAG_BYTES

        token_from(JSON.parse(decrypt(bytes)), now)
      end

      # The key is authenticated with the ciphertext, so an entry copied to
      # another credential's key fails to decrypt instead of being served.
      def decrypt(bytes)
        cipher = start_cipher(:decrypt, bytes.byteslice(0, IV_BYTES))
        cipher.auth_tag = bytes.byteslice(-TAG_BYTES, TAG_BYTES)
        ciphertext = bytes.byteslice(IV_BYTES, bytes.bytesize - IV_BYTES - TAG_BYTES)
        cipher.update(ciphertext) + cipher.final
      end

      def start_cipher(direction, iv)
        cipher = OpenSSL::Cipher.new("aes-256-gcm").public_send(direction)
        cipher.key = @encryption_key
        cipher.iv = iv
        cipher.auth_data = @key
        cipher
      end

      def token_from(payload, now)
        value = payload["access_token"]
        issued_at = payload["issued_at"]
        expires_at = payload["expires_at"]
        return unless value.is_a?(String) && !value.empty?
        return unless issued_at.is_a?(Numeric) && expires_at.is_a?(Numeric)
        return unless issued_at < expires_at && Time.at(expires_at) > now

        Client::CachedToken.new(value: value, issued_at: Time.at(issued_at), expires_at: Time.at(expires_at))
      end
    end
  end
end
