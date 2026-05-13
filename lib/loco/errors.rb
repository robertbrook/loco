module Loco
  class LogoError < StandardError; end

  class StopSignal < RuntimeError; end

  class OutputSignal < RuntimeError
    attr_reader :value
    def initialize(value)
      super("OUTPUT: #{value.inspect}")
      @value = value
    end
  end

  class ThrowSignal < RuntimeError
    attr_reader :tag, :value
    def initialize(tag, value = nil)
      super("THROW #{tag}")
      @tag = tag.to_s.upcase
      @value = value
    end
  end

  class GotoSignal < RuntimeError
    attr_reader :tag
    def initialize(tag)
      super("GOTO #{tag}")
      @tag = tag
    end
  end

  class PauseSignal < RuntimeError; end
end
