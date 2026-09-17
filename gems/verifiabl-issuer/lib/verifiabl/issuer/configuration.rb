# frozen_string_literal: true

module Verifiabl
  module Issuer
    # Immutable settings used to construct one Client. Applications own the
    # resulting client and can place it in their normal dependency container.
    class Configuration
      DEFAULTS = {
        client_id: nil,
        client_secret: nil,
        environment: :production,
        issuer_base_url: nil,
        token_url: nil,
        timeout: 30,
        max_retries: 2,
        on_request: nil,
        on_response: nil,
        on_error: nil
      }.freeze
      private_constant :DEFAULTS

      attr_reader(*DEFAULTS.keys)

      def initialize(**options)
        unknown = options.keys - DEFAULTS.keys
        raise ArgumentError, "unknown keyword: #{unknown.first.inspect}" unless unknown.empty?

        settings = DEFAULTS.merge(options)
        settings[:environment] = normalize_environment(settings[:environment])
        settings.each { |name, value| instance_variable_set("@#{name}", value) }
        freeze
      end

      private

      def normalize_environment(environment)
        value = case environment
        when String then environment.to_sym
        when Symbol then environment
        else raise ArgumentError, "environment must be :production or :sandbox"
        end
        raise ArgumentError, "environment must be :production or :sandbox" unless %i[production sandbox].include?(value)

        value
      end
    end
  end
end
