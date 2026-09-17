# frozen_string_literal: true

require_relative "frame_assets"
require_relative "png_encoder"
require_relative "rendering_assets"

module Verifiabl
  module Issuer
    # Deterministic compositor for the official Verifiabl badge frame.
    module Rendering
      MIN_WIDTH = 480
      VIEWBOX_WIDTH = 96
      HEADER_UNITS = 47
      GAP_UNITS = 7
      QR_Y = HEADER_UNITS + GAP_UNITS
      QR_UNITS = 96
      HEIGHT_UNITS = QR_Y + QR_UNITS
      FINDER_SIZE = 7
      IDEAL_MODULE_PX = 4
      MIN_MODULE_PX = 3
      NAVY = "#010A4F"
      FULL_ERROR_CORRECTION_LADDER = %i[q m l].freeze

      SvgResult = Data.define(:svg, :width, :height, :content, :error_correction_level, :qr_version, :module_px, :degraded)
      PngResult = Data.define(:png, :width, :height, :content, :error_correction_level, :qr_version, :module_px, :degraded)
      Raster = Data.define(:rgba, :width, :height, :content, :error_correction_level, :qr_version, :module_px, :degraded)
      RasterContext = Data.define(:rgba, :width, :denominator, :num_x, :num_y, :pixel_width)
      SvgRequest = Data.define(:verifiabl_reference, :encrypted_pii, :width, :environment, :scan_base_url, :max_error_correction, :error_correction_level)
      PngRequest = Data.define(*SvgRequest.members, :compression_level)
      SVG_DEFAULTS = {width: MIN_WIDTH, environment: :production, scan_base_url: nil, max_error_correction: nil, error_correction_level: nil}.freeze
      PNG_DEFAULTS = SVG_DEFAULTS.merge(width: 720, compression_level: 6).freeze
      private_constant :Raster, :RasterContext, :SvgRequest, :PngRequest, :SVG_DEFAULTS, :PNG_DEFAULTS

      module_function

      def svg(**options)
        request = SvgRequest.new(**SVG_DEFAULTS.merge(options))
        width = validate_svg_width(request.width)
        ladder = error_correction_ladder(request.max_error_correction, request.error_correction_level)
        qr = select_qr(request, width, ladder)
        module_size = QR_UNITS.to_f / qr.modules.length
        module_px = module_size * width / VIEWBOX_WIDTH
        build_svg_result(qr, ladder, width, module_size, module_px)
      end

      def build_svg_result(qr, ladder, width, module_size, module_px)
        height = round(width * HEIGHT_UNITS / VIEWBOX_WIDTH.to_f)
        SvgResult.new(
          svg: svg_document(qr.modules, width, height, module_size).freeze,
          width:,
          height:,
          content: qr.content,
          error_correction_level: qr.error_correction_level,
          qr_version: qr.version,
          module_px: round(module_px),
          degraded: degraded?(qr.error_correction_level, ladder, module_px)
        )
      end
      private_class_method :build_svg_result

      def svg_document(modules, width, height, module_size)
        header = %(<path d="M0 8C0 3.58172 3.58172 0 8 0H88C92.4183 0 96 3.58172 96 8V47H0V8Z" fill="#{NAVY}"/>) + render_header
        %(<svg xmlns="http://www.w3.org/2000/svg" width="#{number(width)}" height="#{number(height)}" viewBox="0 0 96 150" role="img" aria-label="Secured by Verifiabl verification barcode">) +
          %(<rect x="0" y="39" width="96" height="111" fill="#FFFFFF"/>) + header +
          %(<g transform="translate(0 54)"><g shape-rendering="crispEdges">) + render_modules(modules, module_size) +
          %(</g>) + render_finders(modules.length, module_size) + %(</g></svg>)
      end
      private_class_method :svg_document

      def png(**options)
        request = PngRequest.new(**PNG_DEFAULTS.merge(options))
        validate_png_width(request.width)
        ladder = error_correction_ladder(request.max_error_correction, request.error_correction_level)
        build_png_result(compose(request:, ladder:), request.compression_level)
      end

      def build_png_result(raster, compression_level)
        PngResult.new(
          png: PngEncoder.encode(raster.rgba, raster.width, raster.height, compression_level:),
          width: raster.width,
          height: raster.height,
          content: raster.content,
          error_correction_level: raster.error_correction_level,
          qr_version: raster.qr_version,
          module_px: raster.module_px,
          degraded: raster.degraded
        )
      end
      private_class_method :build_png_result

      def compose(**options)
        ladder = options.delete(:ladder)
        request = options.delete(:request) || PngRequest.new(**PNG_DEFAULTS.merge(options))
        qr = select_qr(request, request.width, ladder)
        rgba, raster_width, height = FrameAssets.raster(request.width)
        blit_qr(rgba, raster_width, qr.modules, request.width)
        build_raster(rgba, [raster_width, height], qr, ladder, request.width.to_f / qr.modules.length)
      end
      private_class_method :compose

      def build_raster(rgba, dimensions, qr, ladder, module_px)
        Raster.new(
          rgba: rgba.freeze,
          width: dimensions.fetch(0),
          height: dimensions.fetch(1),
          content: qr.content,
          error_correction_level: qr.error_correction_level,
          qr_version: qr.version,
          module_px: round(module_px),
          degraded: degraded?(qr.error_correction_level, ladder, module_px)
        )
      end
      private_class_method :build_raster

      def select_qr(request, width, ladder)
        ladder.each do |level|
          begin
            qr = Qr.encode_scan_url(
              verifiabl_reference: request.verifiabl_reference,
              encrypted_pii: request.encrypted_pii,
              environment: request.environment,
              scan_base_url: request.scan_base_url,
              error_correction_level: level
            )
          rescue Qr::CapacityError
            next
          end
          return qr if width.to_f / qr.modules.length >= MIN_MODULE_PX
        end
        raise Qr::CapacityError, "The PII is too long to render a scannable barcode in the branded frame at width #{number(width)}, even at the lowest error correction"
      end
      private_class_method :select_qr

      def error_correction_ladder(maximum, legacy)
        raise ArgumentError, "pass either max_error_correction or error_correction_level, not both" if maximum && legacy

        level = normalize_level(maximum || legacy || :m)
        if maximum && level == :l
          raise ArgumentError, "max_error_correction must be :q or :m"
        end
        FULL_ERROR_CORRECTION_LADDER.drop(FULL_ERROR_CORRECTION_LADDER.index(level))
      end
      private_class_method :error_correction_ladder

      def normalize_level(value)
        level = value.respond_to?(:downcase) ? value.downcase.to_sym : value.to_sym
        return level if FULL_ERROR_CORRECTION_LADDER.include?(level)

        raise ArgumentError, "error correction must be :q, :m, or :l"
      rescue NoMethodError
        raise ArgumentError, "error correction must be :q, :m, or :l"
      end
      private_class_method :normalize_level

      def degraded?(level, ladder, module_px)
        level != ladder.first || module_px < IDEAL_MODULE_PX
      end
      private_class_method :degraded?

      def render_modules(modules, module_size)
        size = modules.length
        modules.each_with_index.flat_map do |row, y|
          row.each_with_index.filter_map do |dark, x|
            next unless dark
            next if finder_module?(y, x, size)

            %(<rect x="#{number(x * module_size)}" y="#{number(y * module_size)}" width="#{number(module_size)}" height="#{number(module_size)}" fill="#000000"/>)
          end
        end.join
      end
      private_class_method :render_modules

      def finder_module?(row, column, size)
        top = row < FINDER_SIZE
        left = column < FINDER_SIZE
        right = column >= size - FINDER_SIZE
        bottom = row >= size - FINDER_SIZE
        (top && left) || (top && right) || (bottom && left)
      end
      private_class_method :finder_module?

      def render_finders(size, module_size)
        last = (size - FINDER_SIZE) * module_size
        render_finder(0, 0, module_size) + render_finder(last, 0, module_size) + render_finder(0, last, module_size)
      end
      private_class_method :render_finders

      def render_finder(origin_x, origin_y, module_size)
        outer = FINDER_SIZE * module_size
        inner = outer - module_size * 2
        ring = rounded_rect_path(origin_x, origin_y, outer, module_size * 1.4) + " " +
          rounded_rect_path(origin_x + module_size, origin_y + module_size, inner, module_size)
        %(<path d="#{ring}" fill="#000000" fill-rule="evenodd"/>) + render_finder_dot(origin_x, origin_y, module_size)
      end
      private_class_method :render_finder

      def render_finder_dot(origin_x, origin_y, module_size)
        position_x = number(origin_x + module_size * 2)
        position_y = number(origin_y + module_size * 2)
        size = number(module_size * 3)
        radius = number(module_size * 0.65)
        %(<rect x="#{position_x}" y="#{position_y}" width="#{size}" height="#{size}" rx="#{radius}" fill="#000000"/>)
      end
      private_class_method :render_finder_dot

      def rounded_rect_path(x, y, size, radius)
        radius = [radius, size / 2].min
        top = rounded_rect_top(x, y, size, radius)
        right = rounded_rect_right(x, y, size, radius)
        bottom = rounded_rect_bottom(x, y, size, radius)
        left = rounded_rect_left(x, y, size, radius)
        top + right + bottom + left + "Z"
      end
      private_class_method :rounded_rect_path

      def rounded_rect_top(x, y, size, radius)
        r = number(radius)
        "M#{number(x + radius)} #{number(y)}H#{number(x + size - radius)}A#{r} #{r} 0 0 1 #{number(x + size)} #{number(y + radius)}"
      end
      private_class_method :rounded_rect_top

      def rounded_rect_right(x, y, size, radius)
        r = number(radius)
        "V#{number(y + size - radius)}A#{r} #{r} 0 0 1 #{number(x + size - radius)} #{number(y + size)}"
      end
      private_class_method :rounded_rect_right

      def rounded_rect_bottom(x, y, size, radius)
        r = number(radius)
        "H#{number(x + radius)}A#{r} #{r} 0 0 1 #{number(x)} #{number(y + size - radius)}"
      end
      private_class_method :rounded_rect_bottom

      def rounded_rect_left(x, y, _size, radius)
        r = number(radius)
        "V#{number(y + radius)}A#{r} #{r} 0 0 1 #{number(x + radius)} #{number(y)}"
      end
      private_class_method :rounded_rect_left

      def render_header
        secured_by = RenderingAssets::SECURED_BY_PATH.sub("{color}", "#FFFFFF")
        wordmark = %(<g transform="translate(8 23) scale(1)" fill="#FFFFFF">#{RenderingAssets::WORDMARK_PATHS}</g>)
        %(<g transform="translate(-8 0)">#{secured_by}</g>) + wordmark
      end
      private_class_method :render_header

      def blit_qr(rgba, raster_width, modules, pixel_width)
        context = raster_context(rgba, raster_width, modules.length, pixel_width)
        edges_x, edges_y = raster_edges(context, modules.length)
        draw_raster_modules(context, modules, edges_x, edges_y)

        last = modules.length - FINDER_SIZE
        [[0, 0], [last, 0], [0, last]].each do |module_x, module_y|
          render_raster_finder(context, module_x, module_y)
        end
      end
      private_class_method :blit_qr

      def raster_context(rgba, width, size, pixel_width)
        denominator = VIEWBOX_WIDTH * size
        num_x = ->(position) { pixel_width * QR_UNITS * position }
        num_y = ->(position) { pixel_width * (QR_Y * size + QR_UNITS * position) }
        RasterContext.new(rgba:, width:, denominator:, num_x:, num_y:, pixel_width:)
      end
      private_class_method :raster_context

      def raster_edges(context, size)
        snap = ->(numerator) { (2 * numerator + context.denominator) / (2 * context.denominator) }
        edges_x = (0..size).map { |position| snap.call(context.num_x.call(position)) }
        edges_y = (0..size).map { |position| snap.call(context.num_y.call(position)) }
        [edges_x, edges_y]
      end
      private_class_method :raster_edges

      def draw_raster_modules(context, modules, edges_x, edges_y)
        modules.each_with_index do |row, y|
          row.each_with_index do |dark, x|
            next unless dark
            next if finder_module?(y, x, modules.length)

            fill_black(context, [edges_x[x], edges_y[y]], [edges_x[x + 1], edges_y[y + 1]])
          end
        end
      end
      private_class_method :draw_raster_modules

      def render_raster_finder(context, module_x, module_y)
        shapes = raster_finder_shapes(context, module_x, module_y)
        q_per_pixel = 80 * context.denominator
        raster_finder_pixels(shapes.fetch(:outer), q_per_pixel) do |px, py|
          count = raster_finder_coverage(px, py, q_per_pixel, context.denominator, shapes)
          write_coverage(context, px, py, count) unless count.zero?
        end
      end
      private_class_method :render_raster_finder

      def raster_finder_shapes(context, module_x, module_y)
        module_q = QR_UNITS * context.pixel_width * 80
        radius_unit = QR_UNITS * context.pixel_width
        outer = raster_finder_outer(context, module_x, module_y, module_q, radius_unit)
        {outer:, inner: inset_finder_shape(outer, module_q, 1, 80 * radius_unit), dot: inset_finder_shape(outer, module_q, 2, 52 * radius_unit)}
      end
      private_class_method :raster_finder_shapes

      def raster_finder_outer(context, module_x, module_y, module_q, radius_unit)
        [context.num_x.call(module_x) * 80, context.num_y.call(module_y) * 80, FINDER_SIZE * module_q, 112 * radius_unit]
      end
      private_class_method :raster_finder_outer

      def inset_finder_shape(outer, module_q, inset, radius)
        [outer[0] + inset * module_q, outer[1] + inset * module_q, (FINDER_SIZE - 2 * inset) * module_q, radius]
      end
      private_class_method :inset_finder_shape

      def raster_finder_pixels(outer, q_per_pixel)
        y_range = outer[1] / q_per_pixel...(outer[1] + outer[2] + q_per_pixel - 1) / q_per_pixel
        x_range = outer[0] / q_per_pixel...(outer[0] + outer[2] + q_per_pixel - 1) / q_per_pixel
        y_range.each { |py| x_range.each { |px| yield px, py } }
      end
      private_class_method :raster_finder_pixels

      def raster_finder_coverage(px, py, q_per_pixel, denominator, shapes)
        corner = finder_black?(px * q_per_pixel, py * q_per_pixel, shapes)
        return corner ? 64 : 0 if raster_corners_uniform?(px, py, q_per_pixel, shapes, corner)

        sampled_finder_coverage(px, py, denominator, shapes)
      end
      private_class_method :raster_finder_coverage

      def sampled_finder_coverage(px, py, denominator, shapes)
        8.times.sum do |sy|
          y = (py * 80 + (2 * sy + 1) * 5) * denominator
          8.times.count do |sx|
            finder_black?((px * 80 + (2 * sx + 1) * 5) * denominator, y, shapes)
          end
        end
      end
      private_class_method :sampled_finder_coverage

      def raster_corners_uniform?(px, py, q_per_pixel, shapes, expected)
        left = px * q_per_pixel
        right = (px + 1) * q_per_pixel
        top = py * q_per_pixel
        bottom = (py + 1) * q_per_pixel
        [[right, top], [left, bottom], [right, bottom]].all? { |x, y| finder_black?(x, y, shapes) == expected }
      end
      private_class_method :raster_corners_uniform?

      def finder_black?(x, y, shapes)
        inside_rounded_rect?(x, y, shapes.fetch(:outer)) &&
          (!inside_rounded_rect?(x, y, shapes.fetch(:inner)) || inside_rounded_rect?(x, y, shapes.fetch(:dot)))
      end
      private_class_method :finder_black?

      def write_coverage(context, px, py, count)
        grey = (510 * (64 - count) + 64) / 128
        offset = (py * context.width + px) * 4
        3.times { |channel| context.rgba.setbyte(offset + channel, grey) }
        context.rgba.setbyte(offset + 3, 255)
      end
      private_class_method :write_coverage

      def inside_rounded_rect?(x, y, rectangle)
        x0, y0, size, radius = rectangle
        return false if x < x0 || x > x0 + size || y < y0 || y > y0 + size

        dx = rounded_axis_distance(x, x0, size, radius)
        dy = rounded_axis_distance(y, y0, size, radius)
        dx.zero? || dy.zero? || dx * dx + dy * dy <= radius * radius
      end
      private_class_method :inside_rounded_rect?

      def rounded_axis_distance(value, origin, size, radius)
        return origin + radius - value if value < origin + radius
        return value - (origin + size - radius) if value > origin + size - radius
        0
      end
      private_class_method :rounded_axis_distance

      def fill_black(context, from, to)
        x0, y0 = from
        x1, y1 = to
        black = "\0\0\0\xFF".b
        (y0...y1).each { |y| context.rgba[(y * context.width + x0) * 4, (x1 - x0) * 4] = black * (x1 - x0) }
      end
      private_class_method :fill_black

      def validate_svg_width(value)
        unless value.is_a?(Numeric) && value.finite? && value >= MIN_WIDTH
          raise ArgumentError, "width must be at least #{MIN_WIDTH}"
        end
        value
      end
      private_class_method :validate_svg_width

      def validate_png_width(value)
        return value if value.is_a?(Integer) && FrameAssets::SUPPORTED_WIDTHS.include?(value)

        raise ArgumentError, "width must be one of #{FrameAssets::SUPPORTED_WIDTHS.join(", ")}"
      end
      private_class_method :validate_png_width

      def round(value)
        (value * 100).round / 100.0
      end
      private_class_method :round

      def number(value)
        rounded = round(value)
        (rounded % 1).zero? ? rounded.to_i : rounded
      end
      private_class_method :number
    end
  end
end
