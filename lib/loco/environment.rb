module Loco
  class Environment
    def initialize
      @globals = {}
      @frames = []  # stack of local frame hashes
    end

    def push_frame
      @frames.push({})
    end

    def pop_frame
      @frames.pop
    end

    def make(name, value)
      key = name.to_s.upcase
      # Search from innermost frame outward
      @frames.reverse_each do |frame|
        if frame.key?(key)
          frame[key] = value
          return value
        end
      end
      # Not found in any frame, set in globals
      @globals[key] = value
      value
    end

    def thing(name)
      key = name.to_s.upcase
      @frames.reverse_each do |frame|
        return frame[key] if frame.key?(key)
      end
      raise LogoError, "#{name} has no value" unless @globals.key?(key)
      @globals[key]
    end

    def defined?(name)
      key = name.to_s.upcase
      @frames.reverse_each do |frame|
        return true if frame.key?(key)
      end
      @globals.key?(key)
    end

    def local(name)
      key = name.to_s.upcase
      if @frames.empty?
        @globals[key] ||= nil
      else
        @frames.last[key] = nil unless @frames.last.key?(key)
      end
    end

    def localmake(name, value)
      key = name.to_s.upcase
      if @frames.empty?
        @globals[key] = value
      else
        @frames.last[key] = value
      end
      value
    end

    def global(name)
      key = name.to_s.upcase
      @globals[key] ||= nil
    end

    def global_set(name, value)
      @globals[name.to_s.upcase] = value
    end

    def all_names
      names = Set.new(@globals.keys)
      @frames.each { |f| names.merge(f.keys) }
      names.to_a
    end

    def global_names
      @globals.keys
    end
  end
end
