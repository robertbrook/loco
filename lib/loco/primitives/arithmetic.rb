module Loco
  module Primitives
    module Arithmetic
      def register_arithmetic
        # SUM
        register_primitive('SUM', 2, 2, -1) do |interp, *args|
          args.map { |a| interp.to_number(a) }.sum
        end

        # DIFFERENCE
        register_primitive('DIFFERENCE', 2, 2, 2) do |interp, a, b|
          interp.to_number(a) - interp.to_number(b)
        end

        # MINUS
        register_primitive('MINUS', 1, 1, 1) do |interp, a|
          -interp.to_number(a)
        end

        # PRODUCT
        register_primitive('PRODUCT', 2, 2, -1) do |interp, *args|
          args.map { |a| interp.to_number(a) }.reduce(1, :*)
        end

        # QUOTIENT
        register_primitive('QUOTIENT', 1, 1, 2) do |interp, a, b = nil|
          if b.nil?
            n = interp.to_number(a)
            raise LogoError, "QUOTIENT: division by zero" if n == 0
            1.0 / n
          else
            n = interp.to_number(a)
            d = interp.to_number(b)
            raise LogoError, "QUOTIENT: division by zero" if d == 0
            result = n.to_f / d.to_f
            result == result.to_i ? result.to_i : result
          end
        end

        # REMAINDER
        register_primitive('REMAINDER', 2, 2, 2) do |interp, a, b|
          n1 = interp.to_number(a)
          n2 = interp.to_number(b)
          raise LogoError, "REMAINDER: division by zero" if n2 == 0
          result = n1.to_i.remainder(n2.to_i)
          result
        end

        # MODULO
        register_primitive('MODULO', 2, 2, 2) do |interp, a, b|
          n1 = interp.to_number(a)
          n2 = interp.to_number(b)
          raise LogoError, "MODULO: division by zero" if n2 == 0
          # sign of n2
          n1.to_i % n2.to_i
        end

        # INT
        register_primitive('INT', 1, 1, 1) do |interp, a|
          n = interp.to_number(a).to_f
          n >= 0 ? n.floor : n.ceil
        end

        # ROUND
        register_primitive('ROUND', 1, 1, 1) do |interp, a|
          interp.to_number(a).round
        end

        # SQRT
        register_primitive('SQRT', 1, 1, 1) do |interp, a|
          n = interp.to_number(a).to_f
          raise LogoError, "SQRT: input must be non-negative" if n < 0
          Math.sqrt(n)
        end

        # POWER
        register_primitive('POWER', 2, 2, 2) do |interp, a, b|
          interp.to_number(a) ** interp.to_number(b)
        end

        # EXP
        register_primitive('EXP', 1, 1, 1) do |interp, a|
          Math.exp(interp.to_number(a).to_f)
        end

        # LOG10
        register_primitive('LOG10', 1, 1, 1) do |interp, a|
          n = interp.to_number(a).to_f
          raise LogoError, "LOG10: input must be positive" if n <= 0
          Math.log10(n)
        end

        # LN
        register_primitive('LN', 1, 1, 1) do |interp, a|
          n = interp.to_number(a).to_f
          raise LogoError, "LN: input must be positive" if n <= 0
          Math.log(n)
        end

        # SIN (degrees)
        register_primitive('SIN', 1, 1, 1) do |interp, a|
          deg = interp.to_number(a).to_f
          Math.sin(deg * Math::PI / 180.0)
        end

        # RADSIN
        register_primitive('RADSIN', 1, 1, 1) do |interp, a|
          Math.sin(interp.to_number(a).to_f)
        end

        # COS (degrees)
        register_primitive('COS', 1, 1, 1) do |interp, a|
          deg = interp.to_number(a).to_f
          Math.cos(deg * Math::PI / 180.0)
        end

        # RADCOS
        register_primitive('RADCOS', 1, 1, 1) do |interp, a|
          Math.cos(interp.to_number(a).to_f)
        end

        # ARCTAN
        register_primitive('ARCTAN', 1, 1, 2) do |interp, a, b = nil|
          if b.nil?
            Math.atan(interp.to_number(a).to_f) * 180.0 / Math::PI
          else
            Math.atan2(interp.to_number(a).to_f, interp.to_number(b).to_f) * 180.0 / Math::PI
          end
        end

        # RADARCTAN
        register_primitive('RADARCTAN', 1, 1, 2) do |interp, a, b = nil|
          if b.nil?
            Math.atan(interp.to_number(a).to_f)
          else
            Math.atan2(interp.to_number(a).to_f, interp.to_number(b).to_f)
          end
        end

        # ISEQ
        register_primitive('ISEQ', 2, 2, 2) do |interp, from, to|
          f = interp.to_number(from).to_i
          t = interp.to_number(to).to_i
          if f <= t
            (f..t).to_a
          else
            f.downto(t).to_a
          end
        end

        # RSEQ
        register_primitive('RSEQ', 3, 3, 3) do |interp, from, to, count|
          f = interp.to_number(from).to_f
          t = interp.to_number(to).to_f
          n = interp.to_number(count).to_i
          return [f] if n == 1
          step = (t - f) / (n - 1).to_f
          (0...n).map { |i| f + i * step }
        end

        # LESSP / LESS? / <
        register_primitive('LESSP', 2, 2, 2) do |interp, a, b|
          (interp.to_number(a) < interp.to_number(b)) ? 'true' : 'false'
        end
        register_alias('LESS?', 'LESSP')

        # GREATERP / GREATER? / >
        register_primitive('GREATERP', 2, 2, 2) do |interp, a, b|
          (interp.to_number(a) > interp.to_number(b)) ? 'true' : 'false'
        end
        register_alias('GREATER?', 'GREATERP')

        # LESSEQUALP / LESSEQUAL? / <=
        register_primitive('LESSEQUALP', 2, 2, 2) do |interp, a, b|
          (interp.to_number(a) <= interp.to_number(b)) ? 'true' : 'false'
        end
        register_alias('LESSEQUAL?', 'LESSEQUALP')

        # GREATEREQUALP / GREATEREQUAL? / >=
        register_primitive('GREATEREQUALP', 2, 2, 2) do |interp, a, b|
          (interp.to_number(a) >= interp.to_number(b)) ? 'true' : 'false'
        end
        register_alias('GREATEREQUAL?', 'GREATEREQUALP')

        # RANDOM
        register_primitive('RANDOM', 1, 1, 2) do |interp, a, b = nil|
          if b.nil?
            n = interp.to_number(a).to_i
            raise LogoError, "RANDOM: input must be positive" if n <= 0
            rand(n)
          else
            start = interp.to_number(a).to_i
            stop = interp.to_number(b).to_i
            rand(start..stop)
          end
        end

        # RERANDOM
        register_primitive('RERANDOM', 0, 0, 1) do |interp, seed = nil|
          if seed.nil?
            srand
          else
            srand(interp.to_number(seed).to_i)
          end
          nil
        end

        # FORM
        register_primitive('FORM', 3, 3, 3) do |interp, num, width, precision|
          n = interp.to_number(num).to_f
          w = interp.to_number(width).to_i
          p = interp.to_number(precision).to_i
          sprintf("%#{w}.#{p}f", n)
        end

        # BITAND
        register_primitive('BITAND', 2, 2, -1) do |interp, *args|
          args.map { |a| interp.to_number(a).to_i }.reduce(:&)
        end

        # BITOR
        register_primitive('BITOR', 2, 2, -1) do |interp, *args|
          args.map { |a| interp.to_number(a).to_i }.reduce(:|)
        end

        # BITXOR
        register_primitive('BITXOR', 2, 2, -1) do |interp, *args|
          args.map { |a| interp.to_number(a).to_i }.reduce(:^)
        end

        # BITNOT
        register_primitive('BITNOT', 1, 1, 1) do |interp, a|
          ~interp.to_number(a).to_i
        end

        # ASHIFT
        register_primitive('ASHIFT', 2, 2, 2) do |interp, a, b|
          n = interp.to_number(a).to_i
          s = interp.to_number(b).to_i
          s >= 0 ? n << s : n >> (-s)
        end

        # LSHIFT
        register_primitive('LSHIFT', 2, 2, 2) do |interp, a, b|
          n = interp.to_number(a).to_i
          s = interp.to_number(b).to_i
          s >= 0 ? n << s : n >> (-s)
        end

        # ABS (not in spec but commonly expected)
        register_primitive('ABS', 1, 1, 1) do |interp, a|
          interp.to_number(a).abs
        end

        # MAX (library)
        register_primitive('MAX', 2, 2, -1) do |interp, *args|
          args.map { |a| interp.to_number(a) }.max
        end

        # MIN (library)
        register_primitive('MIN', 2, 2, -1) do |interp, *args|
          args.map { |a| interp.to_number(a) }.min
        end
      end
    end
  end
end
