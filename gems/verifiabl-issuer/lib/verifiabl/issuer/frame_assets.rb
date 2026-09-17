# frozen_string_literal: true

require "zlib"
require_relative "generated/frame_widths"

module Verifiabl
  module Issuer
    module FrameAssets
      Frame = Data.define(:width, :height, :palette, :indices)
      ContainerMetadata = Data.define(:width, :height, :palette_count, :palette_start, :deflated_start, :deflated_length)
      private_constant :ContainerMetadata

      module_function

      def raster(width)
        frame = load(width)
        rgba = String.new(capacity: frame.width * frame.height * 4, encoding: Encoding::BINARY)
        entries = frame.palette.bytes.each_slice(4).map { |bytes| bytes.pack("C4") }
        frame.indices.each_byte { |index| rgba << entries.fetch(index) }
        [rgba, frame.width, frame.height]
      end

      def load(width)
        @cache ||= {}
        @cache[width] ||= parse(File.binread(File.join(__dir__, "assets", "frame-#{width}.vfr1")), expected_width: width)
      end

      def parse(container, expected_width: nil)
        metadata = parse_metadata(container, expected_width)
        indices = inflate_indices(container, metadata)
        validate_indices!(indices, metadata)
        Frame.new(
          width: metadata.width,
          height: metadata.height,
          palette: container.byteslice(metadata.palette_start, metadata.palette_count * 4).freeze,
          indices: indices.freeze
        )
      end

      def parse_metadata(container, expected_width)
        raise "corrupt frame asset: bad magic" unless container.bytesize >= 14 && container.start_with?("VFR1")

        width, height, palette_count = container.byteslice(4, 6).unpack("n3")
        validate_metadata!(width, height, palette_count, expected_width)
        palette_start, deflated_start, deflated_length = parse_layout(container, palette_count)
        ContainerMetadata.new(width:, height:, palette_count:, palette_start:, deflated_start:, deflated_length:)
      end

      def parse_layout(container, palette_count)
        palette_start = 10
        length_offset = palette_start + palette_count * 4
        raise "corrupt frame asset: truncated header" if length_offset + 4 > container.bytesize

        deflated_length = container.byteslice(length_offset, 4).unpack1("N")
        deflated_start = length_offset + 4
        raise "corrupt frame asset: length mismatch" unless deflated_start + deflated_length == container.bytesize
        [palette_start, deflated_start, deflated_length]
      end

      def validate_metadata!(width, height, palette_count, expected_width)
        valid_dimensions = width.positive? && height.positive? && height <= width * 2
        valid_dimensions &&= width == expected_width if expected_width
        raise "corrupt frame asset: unexpected dimensions" unless valid_dimensions
        raise "corrupt frame asset: implausible palette size" unless (1..256).cover?(palette_count)
      end

      def inflate_indices(container, metadata)
        inflater = Zlib::Inflate.new(-Zlib::MAX_WBITS)
        inflater.inflate(container.byteslice(metadata.deflated_start, metadata.deflated_length)) + inflater.finish
      ensure
        inflater&.close
      end

      def validate_indices!(indices, metadata)
        raise "corrupt frame asset: pixel count mismatch" unless indices.bytesize == metadata.width * metadata.height
        raise "corrupt frame asset: palette index out of range" if indices.each_byte.max >= metadata.palette_count
      end

      private_class_method :parse_metadata, :parse_layout, :validate_metadata!, :inflate_indices, :validate_indices!
    end
  end
end
