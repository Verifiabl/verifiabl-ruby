# frozen_string_literal: true

require_relative "test_helper"
require "base64"

class HorizontalRenderingTest < Minitest::Test
  PARTS = {
    verifiabl_reference: "u0FE9WLIS7GYKQnpJPygBw",
    encrypted_pii: Base64.urlsafe_decode64(("Ab3" * 80) + "Zz19-w" + "==")
  }.freeze

  def test_defaults_and_horizontal_frame_geometry
    svg = Verifiabl::Issuer.build_barcode_svg(**PARTS, layout: :horizontal)
    png = Verifiabl::Issuer.build_barcode_png(**PARTS, layout: :horizontal)
    assert_equal [940, 480], [svg.width, svg.height]
    assert_equal [1410, 720], [png.width, png.height]
    assert_includes svg.svg, 'viewBox="0 0 188 96"'
    assert_includes svg.svg, '<rect x="0" y="0" width="103" height="96" fill="#FFFFFF"/>'
    assert_includes svg.svg, '<g transform="translate(103 0)">'
    assert_includes svg.svg, 'fill="#EDEFFF"'
    assert_includes svg.svg, "translate(0.5 0) scale(1.2)"
    assert_includes svg.svg, '<g transform="translate(0 0)"><g shape-rendering="crispEdges">'
    refute_includes svg.svg, "opacity="
    refute_includes svg.svg, "<text"
    refute_includes svg.svg, "clipPath"
  end

  def test_explicit_vertical_is_identical_to_default
    %i[build_barcode_svg build_barcode_png].each do |method|
      assert_equal Verifiabl::Issuer.public_send(method, **PARTS),
        Verifiabl::Issuer.public_send(method, **PARTS, layout: :vertical)
    end
  end

  def test_all_horizontal_png_widths_are_deterministic_and_match_vertical_qr_sizes
    [[940, 480], [1410, 720], [1880, 960], [2820, 1440]].each do |width, vertical_width|
      png = Verifiabl::Issuer.build_barcode_png(**PARTS, layout: :horizontal, width:)
      repeated = Verifiabl::Issuer.build_barcode_png(**PARTS, layout: :horizontal, width:)
      vertical = Verifiabl::Issuer.build_barcode_png(**PARTS, width: vertical_width)
      svg = Verifiabl::Issuer.build_barcode_svg(**PARTS, layout: :horizontal, width:)
      assert_equal [width, vertical_width], [png.width, png.height]
      assert_equal "\x89PNG\r\n\x1A\n".b, png.png.byteslice(0, 8)
      assert_equal png.png, repeated.png
      assert_qr_metadata vertical, png
      assert_qr_metadata svg, png
    end
  end

  def test_continuously_scalable_svg
    svg = Verifiabl::Issuer.build_barcode_svg(**PARTS, layout: :horizontal, width: 1000.5)
    assert_equal 1000.5, svg.width
    assert_equal 510.89, svg.height
  end

  def test_rejects_invalid_layouts_for_both_renderers
    [nil, :diagonal, "horizontal", 0, {}, []].each do |layout|
      %i[build_barcode_svg build_barcode_png].each do |method|
        error = assert_raises(ArgumentError) { Verifiabl::Issuer.public_send(method, **PARTS, layout:) }
        assert_equal "layout must be :vertical or :horizontal", error.message
      end
    end
  end

  def test_rejects_invalid_and_vertical_only_horizontal_widths
    [nil, 0, 480, 720, 939, 940.5, 960, 1440, 2000, Float::NAN, Float::INFINITY, "1410"].each do |width|
      error = assert_raises(ArgumentError) { Verifiabl::Issuer.build_barcode_png(**PARTS, layout: :horizontal, width:) }
      assert_equal "width must be one of 940, 1410, 1880, 2820", error.message
    end
    [nil, 0, 939, Float::NAN, Float::INFINITY, "940"].each do |width|
      error = assert_raises(ArgumentError) { Verifiabl::Issuer.build_barcode_svg(**PARTS, layout: :horizontal, width:) }
      assert_equal "width must be at least 940", error.message
    end
    assert_raises(ArgumentError) { Verifiabl::Issuer.build_barcode_png(**PARTS, width: 1410) }
  end

  def test_capacity_and_degradation_follow_matching_vertical_qr_sizes
    [851, 852, 1590, 1591, 2039].each do |bytes|
      parts = PARTS.merge(encrypted_pii: "\0".b * bytes)
      vertical = Verifiabl::Issuer.build_barcode_svg(**parts)
      horizontal = Verifiabl::Issuer.build_barcode_svg(**parts, layout: :horizontal)
      assert_qr_metadata vertical, horizontal
    end
    %i[vertical horizontal].each do |layout|
      [2100, 3000].each do |bytes|
        assert_raises(Verifiabl::Issuer::Qr::CapacityError) do
          Verifiabl::Issuer.build_barcode_svg(**PARTS.merge(encrypted_pii: "\0".b * bytes), layout:)
        end
      end
    end
    # A wider badge can fix frame-fit, but not absolute QR capacity.
    parts = PARTS.merge(encrypted_pii: "\0".b * 2100)
    vertical = Verifiabl::Issuer.build_barcode_svg(**parts, width: 720)
    horizontal = Verifiabl::Issuer.build_barcode_svg(**parts, layout: :horizontal, width: 1410)
    assert_qr_metadata vertical, horizontal
  end

  def test_horizontal_frames_have_white_qr_boxes_and_gaps_at_every_width
    assets = Verifiabl::Issuer::FrameAssets
    [940, 1410, 1880, 2820].each do |width|
      frame = assets.load(width, layout: :horizontal)
      assert_equal [width, width * 96 / 188], [frame.width, frame.height]
      rgba, = assets.raster(width, layout: :horizontal)
      white = "\xFF".b * (103 * width / 188 * 4)
      frame.height.times do |y|
        assert_equal white, rgba.byteslice(y * width * 4, white.bytesize)
      end
      assert_same frame, assets.load(width, layout: :horizontal)
    end
    assert_raises(ArgumentError) { assets.load(720, layout: :horizontal) }
    assert_raises(ArgumentError) { assets.load(1410) }
    assert_raises(ArgumentError) { assets.load(940, layout: :diagonal) }
  end

  private

  def assert_qr_metadata(expected, actual)
    %i[content error_correction_level qr_version module_px degraded].each do |field|
      assert_equal expected.public_send(field), actual.public_send(field), field.to_s
    end
  end
end
