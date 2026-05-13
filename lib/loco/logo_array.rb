module Loco
  class LogoArray
    attr_accessor :data, :origin

    def initialize(size, origin = 1)
      @origin = origin
      @data = Array.new(size)
    end

    def self.from_array(arr, origin = 1)
      la = new(arr.size, origin)
      la.data = arr.dup
      la
    end

    def [](index)
      @data[index - @origin]
    end

    def []=(index, val)
      @data[index - @origin] = val
    end

    def size
      @data.size
    end

    def to_s
      "{#{@data.map { |e| e.nil? ? '[]' : logo_val_to_s(e) }.join(' ')}}"
    end

    private

    def logo_val_to_s(val)
      case val
      when Array
        "[#{val.map { |e| logo_val_to_s(e) }.join(' ')}]"
      when LogoArray
        val.to_s
      else
        val.to_s
      end
    end
  end
end
