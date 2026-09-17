# frozen_string_literal: true

module Verifiabl
  module Issuer
    class Error < StandardError; end

    class ApiError < Error
      attr_reader :status, :code, :body, :request_id

      def self.valid_body?(body)
        body.is_a?(Hash) && body["code"].is_a?(String) && body["error"].is_a?(String)
      end

      def initialize(status:, body: nil, request_id: nil)
        @status = status
        @body = self.class.valid_body?(body) ? body : nil
        @code = @body ? @body.fetch("code") : "INTERNAL_ERROR"
        @request_id = request_id
        super(error_message)
      end

      private

      def error_message
        @body ? @body.fetch("error") : "Verifiabl API request failed with status #{@status}"
      end
    end

    class IvReuseError < ApiError
      private

      def error_message
        "The encryption IV is already registered. Encrypt the payslip again and rebuild its barcode."
      end
    end

    class AuthError < Error
      attr_reader :status

      def initialize(message, status: nil)
        @status = status
        super(message)
      end
    end

    class TransportError < Error; end

    class TimeoutError < TransportError
      attr_reader :timeout

      def initialize(timeout)
        @timeout = timeout
        super("The Verifiabl API request did not complete within #{timeout} seconds")
      end
    end
  end
end
