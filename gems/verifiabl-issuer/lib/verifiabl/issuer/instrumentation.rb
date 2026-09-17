# frozen_string_literal: true

module Verifiabl
  module Issuer
    module Instrumentation
      module_function

      def observe_request(payload, on_request:, on_response:, on_error:, monotonic_clock:)
        started_at = monotonic_clock.call
        emit(:request, payload, on_request)
        response = yield
        emit(
          :response,
          payload.merge(
            status: response.status,
            elapsed_ms: elapsed_ms(started_at, monotonic_clock),
            request_id: Client.request_id(response.headers)
          ),
          on_response
        )
        response
      rescue => error
        emit(
          :error,
          payload.merge(elapsed_ms: elapsed_ms(started_at, monotonic_clock), error: error),
          on_error
        )
        raise
      end

      def emit(type, payload, callback)
        event = payload.freeze
        begin
          callback&.call(event)
        rescue
          # Observability hooks must not change API request behaviour.
        end
      end
      private_class_method :emit

      def elapsed_ms(started_at, monotonic_clock)
        (monotonic_clock.call - started_at) * 1000
      end
      private_class_method :elapsed_ms
    end
  end
end
