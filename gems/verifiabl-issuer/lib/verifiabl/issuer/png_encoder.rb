# frozen_string_literal: true

require "zlib"

module Verifiabl
  module Issuer
    module PngEncoder
      SIGNATURE = "\x89PNG\r\n\x1A\n".b.freeze
      MAX_PALETTE = 256

      module_function

      def encode(rgba, width, height, compression_level: Zlib::DEFAULT_COMPRESSION)
        unless compression_level.is_a?(Integer) && (0..9).cover?(compression_level)
          raise ArgumentError, "compression_level must be an integer between 0 and 9"
        end

        palette = build_palette(rgba, width, height)
        palette ? encode_indexed(palette, width, height, compression_level) : encode_truecolor(rgba, width, height, compression_level)
      end

      def build_palette(rgba, width, height)
        colors = {}
        rgb = +"".b
        alpha = []
        indices = String.new(capacity: width * height, encoding: Encoding::BINARY)
        (width * height).times do |pixel|
          components = rgba.byteslice(pixel * 4, 4).bytes
          color = components.reduce(0) { |value, component| value * 256 + component }
          index = colors[color]
          unless index
            return nil if alpha.length >= MAX_PALETTE
            index = add_palette_color(colors, rgb, alpha, color, components)
          end
          indices << index
        end
        [rgb, alpha, indices]
      end
      private_class_method :build_palette

      def add_palette_color(colors, rgb, alpha, color, components)
        index = alpha.length
        colors[color] = index
        rgb << components.fetch(0) << components.fetch(1) << components.fetch(2)
        alpha << components.fetch(3)
        index
      end
      private_class_method :add_palette_color

      def encode_indexed(palette, width, height, level)
        rgb, alpha, indices = palette
        raw = scanlines(indices, width, height)
        alpha.pop while alpha.last == 255
        chunks = [SIGNATURE, ihdr(width, height, 3), chunk("PLTE", rgb)]
        chunks << chunk("tRNS", alpha.pack("C*")) unless alpha.empty?
        chunks << chunk("IDAT", Zlib::Deflate.deflate(raw, level)) << chunk("IEND", "".b)
        chunks.join.freeze
      end
      private_class_method :encode_indexed

      def encode_truecolor(rgba, width, height, level)
        raw = scanlines(rgba, width * 4, height)
        (SIGNATURE + ihdr(width, height, 6) + chunk("IDAT", Zlib::Deflate.deflate(raw, level)) + chunk("IEND", "".b)).freeze
      end
      private_class_method :encode_truecolor

      def scanlines(data, stride, height)
        String.new(capacity: (stride + 1) * height, encoding: Encoding::BINARY).tap do |raw|
          height.times { |y| raw << 0 << data.byteslice(y * stride, stride) }
        end
      end
      private_class_method :scanlines

      def ihdr(width, height, color_type)
        chunk("IHDR", [width, height, 8, color_type, 0, 0, 0].pack("NNC5"))
      end
      private_class_method :ihdr

      def chunk(type, data)
        payload = type.b + data
        [data.bytesize].pack("N") + payload + [Zlib.crc32(payload)].pack("N")
      end
      private_class_method :chunk
    end
  end
end
