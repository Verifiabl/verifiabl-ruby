# frozen_string_literal: true

require "digest"
require_relative "test_helper"

class QrTest < Minitest::Test
  REFERENCE = "AbCdEfGhIjKlMnOpQrStUv"
  PREFIX = "https://v.sandbox.verifiabl.io/v/#{REFERENCE}#2."
  CANONICAL_MATRICES = [
    [6, 5, 2, "fdfe73d399d058f3c3da626263f817fdd91a63ffdd777931abeadfa98a1c67b5"],
    [36, 6, 2, "8b292757bf3d1543e99ac20ec74ab3081a2e9b08584d3bd20dd6d84cd8ca567f"],
    [128, 10, 4, "7af508ae0a95d7c81430fcc050546ad427924a6c06ca747d49ded89792a198d5"],
    [320, 15, 2, "1dee3231eedb6c74cdbdfa2890713fee83bd26200acbc346ac2d9fb7a316fee9"],
    [1024, 28, 1, "319d946299a770b1f06a41c37b5f788c38a81a98890c4a2850d5615ffa665d43"]
  ].freeze

  def test_matches_node_and_dotnet_canonical_versions_masks_and_matrices
    CANONICAL_MATRICES.each do |byte_length, version, mask, sha256|
      result = build(byte_length)

      assert_equal version, result.version, "version for #{byte_length} ciphertext bytes"
      assert_equal mask, result.mask_pattern, "mask for #{byte_length} ciphertext bytes"
      assert_equal sha256, matrix_digest(result.modules), "matrix for #{byte_length} ciphertext bytes"
    end
  end

  def test_uses_explicit_byte_and_alphanumeric_segments
    result = build(36)

    assert_equal %i[byte_8bit alphanumeric], result.segment_modes
    assert result.content.start_with?(PREFIX)
    assert_match(/\A[A-Z2-7]+\z/, result.content.delete_prefix(PREFIX))
  end

  def test_counts_utf8_bytes_and_matches_the_canonical_unicode_matrix
    result = Verifiabl::Issuer::Qr.encode_segments(
      [{data: "給与明細", mode: :byte_8bit}],
      content: "給与明細",
      error_correction_level: :m
    )

    assert_equal 1, result.version
    assert_equal 4, result.mask_pattern
    assert_equal "d3def4800be76201aab49d5803db158fb948fac66e869ad4066e5d94a699fcbc", matrix_digest(result.modules)
  end

  def test_reports_capacity_errors_without_leaking_content
    secret = deterministic_bytes(3_000)

    error = assert_raises(Verifiabl::Issuer::Qr::CapacityError) do
      Verifiabl::Issuer::Qr.encode_scan_url(
        verifiabl_reference: REFERENCE,
        encrypted_pii: secret,
        environment: :sandbox
      )
    end

    assert_includes error.message, "too large"
    refute_includes error.message, secret
  end

  def test_rejects_unsupported_modes_and_error_correction_levels
    assert_raises(ArgumentError) do
      Verifiabl::Issuer::Qr.encode_segments([{data: "123", mode: :numeric}], content: "123")
    end
    assert_raises(ArgumentError) { build(6, error_correction_level: :h) }
  end

  private

  def build(byte_length, **options)
    Verifiabl::Issuer::Qr.encode_scan_url(
      verifiabl_reference: REFERENCE,
      encrypted_pii: deterministic_bytes(byte_length),
      environment: :sandbox,
      **options
    )
  end

  def deterministic_bytes(length)
    (0...length).map { |index| index % 256 }.pack("C*")
  end

  def matrix_digest(modules)
    Digest::SHA256.hexdigest(modules.flatten.map { |dark| dark ? "1" : "0" }.join)
  end
end
