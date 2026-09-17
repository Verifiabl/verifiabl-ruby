# frozen_string_literal: true

require "rqrcode_core"

module Verifiabl
  module Issuer
    # QR matrix generation shared by the future SVG and PNG compositors.
    #
    # rqrcode_core produces the same codewords as the Node and .NET encoders,
    # but its built-in mask penalty predates the current ISO rules. CanonicalCode
    # replaces only mask selection so that all SDKs produce the same matrix.
    module Qr
      MASK_ORDER = [2, 3, 7, 4, 6, 5, 0, 1].freeze
      MODES = %i[byte_8bit alphanumeric].freeze

      Result = Data.define(:content, :modules, :version, :mask_pattern, :error_correction_level, :segment_modes)

      class CapacityError < ArgumentError; end

      class CanonicalCode < RQRCodeCore::QRCode
        attr_reader :mask_pattern

        private

        def get_best_mask_pattern
          lowest_penalty = Float::INFINITY

          MASK_ORDER.each do |candidate|
            # Include real format/version bits, matching the Node and .NET
            # candidates rather than rqrcode_core's legacy test matrix.
            make_impl(false, candidate)
            penalty = Qr.penalty(modules)
            next unless penalty < lowest_penalty

            @mask_pattern = candidate
            lowest_penalty = penalty
          end

          @mask_pattern
        end
      end
      private_constant :CanonicalCode

      module_function

      def encode_scan_url(verifiabl_reference:, encrypted_pii:, environment: :production, scan_base_url: nil, error_correction_level: :m)
        parts = Payload.scan_url_parts(
          verifiabl_reference: verifiabl_reference,
          encrypted_pii: encrypted_pii,
          environment: environment,
          scan_base_url: scan_base_url
        )
        encode_segments(
          [
            {data: parts.byte_prefix.b, mode: :byte_8bit},
            {data: parts.alphanumeric_ciphertext, mode: :alphanumeric}
          ],
          content: parts.content,
          error_correction_level: error_correction_level
        )
      end

      def encode_segments(segments, content:, error_correction_level: :m)
        level = normalize_error_correction_level(error_correction_level)
        normalized = segments.map { |segment| normalize_segment(segment) }
        build_result(CanonicalCode.new(normalized, level:), normalized, content, level)
      rescue RQRCodeCore::QRCodeRunTimeError => error
        raise unless error.message.include?("exceed maximum capacity")

        raise CapacityError, "The QR content is too large to encode at error correction #{level.to_s.upcase}"
      end

      def normalize_segment(segment)
        mode = segment.fetch(:mode).to_sym
        raise ArgumentError, "QR segment mode must be :byte_8bit or :alphanumeric" unless MODES.include?(mode)
        {data: String(segment.fetch(:data)), mode:}
      end
      private_class_method :normalize_segment

      def build_result(code, segments, content, level)
        Result.new(
          content:,
          modules: code.modules.map { |row| row.map { |value| !!value }.freeze }.freeze,
          version: code.version,
          mask_pattern: code.mask_pattern,
          error_correction_level: level,
          segment_modes: segments.map { |segment| segment.fetch(:mode) }.freeze
        )
      end
      private_class_method :build_result

      def penalty(modules)
        size = modules.length
        at = module_reader(modules)
        same_color_penalty(size, at) + block_penalty(size, at) + finder_penalty(size, at) + balance_penalty(modules)
      end

      def module_reader(modules)
        size = modules.length
        lambda do |row, column|
          next false if row.negative? || column.negative? || row >= size || column >= size
          modules.fetch(row).fetch(column)
        end
      end
      private_class_method :module_reader

      def balance_penalty(modules)
        size = modules.length
        dark = modules.sum { |row| row.count(true) }
        10 * ((dark - ((size * size) / 2)).abs / ((size * size) / 20))
      end
      private_class_method :balance_penalty

      def same_color_penalty(size, at)
        penalty = 0
        size.times do |outer|
          [false, true].each do |vertical|
            previous = nil
            run = 0
            size.times do |inner|
              value = vertical ? at.call(inner, outer) : at.call(outer, inner)
              if value == previous
                run += 1
              else
                penalty += 3 + run - 5 if run >= 5
                previous = value
                run = 1
              end
            end
            penalty += 3 + run - 5 if run >= 5
          end
        end
        penalty
      end
      private_class_method :same_color_penalty

      def block_penalty(size, at)
        penalty = 0
        (size - 1).times do |row|
          (size - 1).times do |column|
            value = at.call(row, column)
            penalty += 3 if at.call(row, column + 1) == value && at.call(row + 1, column) == value && at.call(row + 1, column + 1) == value
          end
        end
        penalty
      end
      private_class_method :block_penalty

      def finder_penalty(size, at)
        size.times.sum do |outer|
          [false, true].sum do |vertical|
            finder_line_penalty(size, line_reader(at, outer, vertical))
          end
        end
      end
      private_class_method :finder_penalty

      def line_reader(at, outer, vertical)
        lambda do |offset|
          value = vertical ? at.call(offset, outer) : at.call(outer, offset)
          value ? 1 : 0
        end
      end
      private_class_method :line_reader

      def finder_line_penalty(size, read)
        pattern = [1, 0, 1, 1, 1, 0, 1]
        (size - 6).times.sum do |start|
          next 0 unless pattern.each_with_index.all? { |value, offset| read.call(start + offset) == value }

          left_four_right_one = all_light?(read, start - 4, 4) && read.call(start + 7).zero?
          left_one_right_four = read.call(start - 1).zero? && all_light?(read, start + 7, 4)
          (left_four_right_one || left_one_right_four) ? 40 : 0
        end
      end
      private_class_method :finder_line_penalty

      def all_light?(read, start, length)
        length.times.all? { |offset| read.call(start + offset).zero? }
      end
      private_class_method :all_light?

      def normalize_error_correction_level(value)
        level = value.respond_to?(:to_sym) ? value.to_sym : nil
        return level if %i[l m q].include?(level)

        raise ArgumentError, "error_correction_level must be :l, :m, or :q"
      end
      private_class_method :normalize_error_correction_level
    end
  end
end
