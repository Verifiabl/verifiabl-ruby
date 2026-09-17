# frozen_string_literal: true

require_relative "test_helper"

class VerifiablIssuerTest < Minitest::Test
  def test_has_a_version
    refute_nil Verifiabl::Issuer::VERSION
  end

  def test_configuration_defaults_to_production
    assert_equal :production, Verifiabl::Issuer::Configuration.new.environment
  end

  def test_configuration_accepts_a_string_environment
    configuration = Verifiabl::Issuer::Configuration.new(environment: "sandbox")

    assert_equal :sandbox, configuration.environment
    assert_predicate configuration, :frozen?
  end

  def test_configuration_rejects_an_unknown_environment
    error = assert_raises(ArgumentError) do
      Verifiabl::Issuer::Configuration.new(environment: :staging)
    end

    assert_equal "environment must be :production or :sandbox", error.message
  end

  def test_configuration_rejects_non_symbol_or_string_environments
    [nil, Object.new].each do |value|
      error = assert_raises(ArgumentError) do
        Verifiabl::Issuer::Configuration.new(environment: value)
      end

      assert_equal "environment must be :production or :sandbox", error.message
    end
  end
end
