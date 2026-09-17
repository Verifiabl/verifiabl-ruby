# frozen_string_literal: true

require "json"
require "timeout"
require_relative "test_helper"

class ClientLifecycleTest < Minitest::Test
  def test_refreshes_tokens_after_fork_when_parent_mutex_was_locked
    skip "fork is unavailable" unless Process.respond_to?(:fork)

    client = client_with_successful_transport
    mutex = client.instance_variable_get(:@token_mutex)
    locked = Queue.new
    release = Queue.new
    holder = Thread.new do
      mutex.synchronize do
        locked << true
        release.pop
      end
    end
    locked.pop

    reader, writer = IO.pipe
    child_pid = fork do
      reader.close
      begin
        Timeout.timeout(1) do
          client.register_non_pii(verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv", **registration)
        end
        writer.write("ok")
      rescue => error
        writer.write("#{error.class}: #{error.message}")
      ensure
        writer.close
      end
      exit! 0
    end
    writer.close
    result = Timeout.timeout(3) { reader.read }
    Process.wait(child_pid)

    assert_equal "ok", result
  ensure
    release&.push(true) if holder&.alive?
    holder&.join
    reader&.close
    writer&.close
  end

  private

  def client_with_successful_transport
    configuration = Verifiabl::Issuer::Configuration.new(
      client_id: "client",
      client_secret: "secret",
      environment: :sandbox
    )
    transport = lambda do |**request|
      body = if request.fetch(:url).include?("/oauth/token")
        {access_token: "token", token_type: "Bearer", expires_in: 3600}
      else
        {verifiabl_reference: "AbCdEfGhIjKlMnOpQrStUv"}
      end
      Verifiabl::Issuer::Client::Response.new(status: 200, headers: {}, body: JSON.generate(body))
    end
    Verifiabl::Issuer::Client.new(configuration, transport: transport)
  end

  def registration
    {
      schema: "au.payslip.v1",
      issued_at: "2026-06-11T00:00:00Z",
      payslip_non_pii: {period_start: "2026-06-01"},
      encryption_metadata: {iv: "\0".b * 12, tag: "\0".b * 16}
    }
  end
end
