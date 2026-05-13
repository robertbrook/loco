module Loco
  module Primitives
    module Communication
      def register_communication
        # PRINT / PR
        register_primitive('PRINT', 1, 1, -1) do |interp, *args|
          args.each do |arg|
            interp.logo_print_output(interp.logo_print_str(arg))
          end
          nil
        end
        register_alias('PR', 'PRINT')

        # TYPE
        register_primitive('TYPE', 1, 1, -1) do |interp, *args|
          args.each do |arg|
            interp.logo_type_output(interp.logo_print_str(arg))
          end
          nil
        end

        # SHOW
        register_primitive('SHOW', 1, 1, -1) do |interp, *args|
          args.each do |arg|
            interp.logo_print_output(interp.logo_show_str(arg))
          end
          nil
        end

        # READLIST / RL
        register_primitive('READLIST', 0, 0, 0) do |interp|
          line = interp.read_line
          line ||= ''
          tokens = Tokenizer.new(line.chomp).tokenize
          stream = TokenStream.new(tokens)
          result = []
          until stream.empty?
            tok = stream.peek
            if tok.type == :name
              stream.consume
              result << tok.value
            elsif tok.type == :word
              stream.consume
              result << tok.value
            elsif tok.type == :number
              stream.consume
              result << tok.value
            elsif tok.type == :left_bracket
              result << interp.collect_list(stream)
            else
              stream.consume
              result << tok.value.to_s
            end
          end
          result
        end
        register_alias('RL', 'READLIST')

        # READWORD / RW
        register_primitive('READWORD', 0, 0, 0) do |interp|
          line = interp.read_line
          line ? line.chomp : nil
        end
        register_alias('RW', 'READWORD')

        # READRAWLINE
        register_primitive('READRAWLINE', 0, 0, 0) do |interp|
          line = interp.read_line
          line ? line.chomp : nil
        end

        # READCHAR / RC
        register_primitive('READCHAR', 0, 0, 0) do |interp|
          ch = interp.read_char
          ch || ''
        end
        register_alias('RC', 'READCHAR')

        # READCHARS / RCS
        register_primitive('READCHARS', 1, 1, 1) do |interp, num|
          n = interp.to_number(num).to_i
          chars = ''
          n.times do
            ch = interp.read_char
            break unless ch
            chars += ch
          end
          chars
        end
        register_alias('RCS', 'READCHARS')

        # SHELL - UCB Logo primitive; executes the given shell command string.
        # NOTE: SHELL is inherently unsafe and executes arbitrary commands.
        register_primitive('SHELL', 1, 1, 2) do |interp, command, wordflag = nil|
          require 'open3'
          cmd = interp.logo_to_word(command)
          result, = Open3.capture2e('/bin/sh', '-c', cmd)
          if wordflag && interp.logo_true?(wordflag)
            result.chomp
          else
            result.lines.map(&:chomp)
          end
        end

        # KEYP / KEY?
        register_primitive('KEYP', 0, 0, 0) do |interp|
          # Simplified: check if STDIN has data
          'false'
        end
        register_alias('KEY?', 'KEYP')

        # CLEARTEXT / CT
        register_primitive('CLEARTEXT', 0, 0, 0) do |interp|
          print "\e[2J\e[H"
          nil
        end
        register_alias('CT', 'CLEARTEXT')

        # SETCURSOR
        register_primitive('SETCURSOR', 1, 1, 1) do |interp, vec|
          raise LogoError, "SETCURSOR: input must be a list of two numbers" unless vec.is_a?(Array) && vec.size == 2
          col = interp.to_number(vec[0]).to_i
          row = interp.to_number(vec[1]).to_i
          print "\e[#{row + 1};#{col + 1}H"
          nil
        end

        # CURSOR
        register_primitive('CURSOR', 0, 0, 0) do |interp|
          [0, 0]
        end

        # SETMARGINS
        register_primitive('SETMARGINS', 1, 1, 1) do |interp, vec|
          nil
        end
      end
    end
  end
end
