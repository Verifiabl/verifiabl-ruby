# frozen_string_literal: true

require_relative "test_helper"
require "base64"
require "json"
require "zlib"

class RenderingTest < Minitest::Test
  REFERENCE = "u0FE9WLIS7GYKQnpJPygBw"
  CIPHERTEXT = Base64.urlsafe_decode64(("Ab3" * 80) + "Zz19-w" + "==")
  FIXTURES = File.expand_path("fixtures/rendering", __dir__)

  def test_svg_exactly_matches_the_node_renderer
    result = Verifiabl::Issuer.build_barcode_svg(verifiabl_reference: REFERENCE, encrypted_pii: CIPHERTEXT)

    assert_equal File.read(File.join(FIXTURES, "node-svg-default-480.svg")), result.svg
    assert_equal 480, result.width
    assert_equal 750, result.height
    assert_equal :m, result.error_correction_level
    assert_equal 12, result.qr_version
    assert_equal 7.38, result.module_px
    refute result.degraded
    refute_includes result.svg, "<text"
    assert_includes result.svg, 'fill-rule="evenodd"'
  end

  def test_other_svg_profiles_exactly_match_the_node_renderer
    scenarios = [
      ["short-default-480", "\0".b, 480, :production, nil],
      ["sandbox-q-720", CIPHERTEXT, 720, :sandbox, :q]
    ]

    scenarios.each do |name, ciphertext, width, environment, maximum|
      result = Verifiabl::Issuer.build_barcode_svg(
        verifiabl_reference: REFERENCE,
        encrypted_pii: ciphertext,
        width:,
        environment:,
        max_error_correction: maximum
      )
      assert_equal File.read(File.join(FIXTURES, "node-svg-#{name}.svg")), result.svg
      assert_metadata expected_metadata("svg", name), result
    end
  end

  def test_png_rasters_exactly_match_the_node_compositor
    scenarios = [
      ["png-default-1440", CIPHERTEXT, 1440, :production, nil],
      ["png-default-720", CIPHERTEXT, 720, :production, nil],
      ["png-short-default-480", "\0".b, 480, :production, nil],
      ["png-sandbox-q-480", CIPHERTEXT, 480, :sandbox, :q]
    ]
    rendering = Verifiabl::Issuer::Rendering

    scenarios.each do |name, ciphertext, width, environment, maximum|
      ladder = rendering.send(:error_correction_ladder, maximum, nil)
      raster = rendering.send(
        :compose,
        verifiabl_reference: REFERENCE,
        encrypted_pii: ciphertext,
        width:,
        environment:,
        scan_base_url: nil,
        ladder:
      )
      expected = inflate_raw(File.binread(File.join(FIXTURES, "node-#{name}.rgba.deflate")))

      assert_equal expected, raster.rgba
      assert_metadata expected_metadata("png", name), raster
    end
  end

  def test_builds_deterministic_valid_png
    first = Verifiabl::Issuer.build_barcode_png(verifiabl_reference: REFERENCE, encrypted_pii: CIPHERTEXT, width: 480)
    second = Verifiabl::Issuer.build_barcode_png(verifiabl_reference: REFERENCE, encrypted_pii: CIPHERTEXT, width: 480)

    assert_equal "\x89PNG\r\n\x1A\n".b, first.png.byteslice(0, 8)
    assert_equal first.png, second.png
    assert_equal 750, first.height
  end

  def test_uses_requested_error_correction_ceiling
    result = Verifiabl::Issuer.build_barcode_svg(
      verifiabl_reference: REFERENCE,
      encrypted_pii: CIPHERTEXT,
      width: 720,
      max_error_correction: :q
    )

    assert_equal :q, result.error_correction_level
    refute result.degraded
  end

  def test_rejects_unsupported_png_widths
    [479, 481, 640, 720.5].each do |width|
      error = assert_raises(ArgumentError) do
        Verifiabl::Issuer.build_barcode_png(verifiabl_reference: REFERENCE, encrypted_pii: CIPHERTEXT, width:)
      end
      assert_equal "width must be one of 480, 720, 960, 1440", error.message
    end
  end

  def test_rejects_unscannably_small_svg
    assert_raises(ArgumentError) do
      Verifiabl::Issuer.build_barcode_svg(verifiabl_reference: REFERENCE, encrypted_pii: CIPHERTEXT, width: 479)
    end
  end

  private

  def expected_metadata(format, name)
    JSON.parse(File.read(File.join(FIXTURES, "node-#{format}-meta.json"))).fetch(name)
  end

  def assert_metadata(expected, actual)
    assert_equal expected.fetch("content"), actual.content
    assert_equal expected.fetch("width"), actual.width
    assert_equal expected.fetch("height"), actual.height
    assert_equal expected.fetch("errorCorrectionLevel").downcase.to_sym, actual.error_correction_level
    assert_equal expected.fetch("qrVersion"), actual.qr_version
    assert_equal expected.fetch("modulePx"), actual.module_px
    assert_equal expected.fetch("degraded"), actual.degraded
  end

  def inflate_raw(bytes)
    inflater = Zlib::Inflate.new(-Zlib::MAX_WBITS)
    inflater.inflate(bytes) + inflater.finish
  ensure
    inflater&.close
  end
end
