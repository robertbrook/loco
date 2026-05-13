module Loco
  class Token
    attr_reader :type, :value

    TYPES = %i[
      number word name variable
      left_bracket right_bracket
      left_paren right_paren
      left_brace right_brace
      infix_op newline
    ].freeze

    def initialize(type, value)
      @type = type
      @value = value
    end

    def to_s
      "#<Token #{@type} #{@value.inspect}>"
    end

    def inspect
      to_s
    end
  end
end
