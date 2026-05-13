module Loco
  class Tokenizer
    INFIX_TWO_CHAR = %w[<> <= >=].freeze
    INFIX_ONE_CHAR = %w[+ - * / = < >].freeze

    def initialize(source)
      @source = source.dup
      @pos = 0
      @tokens = []
      @inside_brackets = 0
    end

    def tokenize
      while @pos < @source.length
        ch = @source[@pos]

        case ch
        when ' ', "\t", "\r"
          @pos += 1
        when "\n"
          @tokens << Token.new(:newline, "\n")
          @pos += 1
        when ';'
          # Comment: skip to end of line
          while @pos < @source.length && @source[@pos] != "\n"
            @pos += 1
          end
        when '~'
          # Line continuation
          @pos += 1
          skip_newline
        when '"'
          @tokens << read_quoted_word
        when ':'
          @tokens << read_variable
        when '['
          @tokens << Token.new(:left_bracket, '[')
          @inside_brackets += 1
          @pos += 1
        when ']'
          @tokens << Token.new(:right_bracket, ']')
          @inside_brackets -= 1
          @pos += 1
        when '('
          @tokens << Token.new(:left_paren, '(')
          @pos += 1
        when ')'
          @tokens << Token.new(:right_paren, ')')
          @pos += 1
        when '{'
          @tokens << Token.new(:left_brace, '{')
          @pos += 1
        when '}'
          @tokens << Token.new(:right_brace, '}')
          @pos += 1
        else
          if @inside_brackets > 0
            # Inside brackets: words are only delimited by spaces and brackets
            tok = read_bracket_word
            @tokens << tok if tok
          elsif is_infix_start?(ch)
            @tokens << read_infix_op
          elsif digit_or_dot?(ch)
            @tokens << read_number
          else
            tok = read_name
            @tokens << tok if tok
          end
        end
      end
      @tokens
    end

    private

    def skip_newline
      while @pos < @source.length && (@source[@pos] == "\n" || @source[@pos] == "\r")
        @pos += 1
      end
    end

    def is_infix_start?(ch)
      INFIX_ONE_CHAR.include?(ch)
    end

    def digit_or_dot?(ch)
      ch =~ /[0-9]/ || (ch == '.' && @pos + 1 < @source.length && @source[@pos + 1] =~ /[0-9]/)
    end

    def read_quoted_word
      @pos += 1 # skip "
      start = @pos
      while @pos < @source.length
        ch = @source[@pos]
        break if ch =~ /[\s\[\](){}"]/ # " also terminates (handles "" as empty word)
        @pos += 1
      end
      value = @source[start...@pos]
      Token.new(:word, value)
    end

    def read_variable
      @pos += 1 # skip :
      start = @pos
      while @pos < @source.length
        ch = @source[@pos]
        break if ch =~ /[\s\[\](){}+\-*\/=<>]/
        @pos += 1
      end
      name = @source[start...@pos].upcase
      Token.new(:variable, name)
    end

    def read_number
      start = @pos
      # Handle potential negative handled by caller
      @pos += 1 while @pos < @source.length && @source[@pos] =~ /[0-9]/
      if @pos < @source.length && @source[@pos] == '.' && @pos + 1 < @source.length && @source[@pos + 1] =~ /[0-9]/
        @pos += 1
        @pos += 1 while @pos < @source.length && @source[@pos] =~ /[0-9]/
      end
      # Handle scientific notation
      if @pos < @source.length && @source[@pos] =~ /[eE]/
        @pos += 1
        @pos += 1 if @pos < @source.length && @source[@pos] =~ /[+\-]/
        @pos += 1 while @pos < @source.length && @source[@pos] =~ /[0-9]/
      end
      val_str = @source[start...@pos]
      val = val_str.include?('.') || val_str =~ /[eE]/ ? val_str.to_f : val_str.to_i
      Token.new(:number, val)
    end

    def read_infix_op
      two_char = @source[@pos, 2]
      if INFIX_TWO_CHAR.include?(two_char)
        @pos += 2
        Token.new(:infix_op, two_char)
      else
        ch = @source[@pos]
        @pos += 1
        Token.new(:infix_op, ch)
      end
    end

    def read_name
      start = @pos
      while @pos < @source.length
        ch = @source[@pos]
        break if ch =~ /[\s\[\](){}]/
        # Don't break on infix ops inside names (e.g. LESS? has ?)
        # But do break on operators that clearly separate tokens
        break if is_infix_start?(ch) && @pos > start
        @pos += 1
      end
      return nil if @pos == start
      value = @source[start...@pos]
      # Check if it's a number (can happen after sign)
      if value =~ /\A-?[0-9]+(\.[0-9]+)?([eE][+\-]?[0-9]+)?\z/
        val = value.include?('.') || value =~ /[eE]/ ? value.to_f : value.to_i
        return Token.new(:number, val)
      end
      Token.new(:name, value.upcase)
    end

    def read_bracket_word
      start = @pos
      while @pos < @source.length
        ch = @source[@pos]
        break if ch =~ /[\s\[\]]/
        @pos += 1
      end
      return nil if @pos == start
      value = @source[start...@pos]
      # Inside brackets, check if it looks like a number
      if value =~ /\A-?[0-9]+(\.[0-9]+)?([eE][+\-]?[0-9]+)?\z/
        val = value.include?('.') || value =~ /[eE]/ ? value.to_f : value.to_i
        return Token.new(:number, val)
      end
      Token.new(:name, value)
    end
  end

  class TokenStream
    def initialize(tokens)
      @tokens = tokens  # keep newlines; callers skip them as needed
      @pos = 0
    end

    def peek
      @tokens[@pos]
    end

    # Peek skipping newlines (for use in arg-reading loops)
    def peek_skip_newlines
      pos = @pos
      pos += 1 while @tokens[pos]&.type == :newline
      @tokens[pos]
    end

    def skip_newlines
      @pos += 1 while @tokens[@pos]&.type == :newline
    end

    def peek_at(offset)
      @tokens[@pos + offset]
    end

    def consume
      tok = @tokens[@pos]
      @pos += 1
      tok
    end

    def empty?
      @pos >= @tokens.length
    end

    def pos
      @pos
    end

    def pos=(p)
      @pos = p
    end

    def remaining
      @tokens[@pos..]
    end

    def to_a
      @tokens.dup
    end

    def has_more?
      !empty?
    end
  end
end
