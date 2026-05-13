module Loco
  class Procedure
    attr_reader :name, :inputs, :body, :min_inputs, :default_inputs, :max_inputs, :type

    def initialize(name:, inputs: [], body: nil, min_inputs: 0, default_inputs: 0, max_inputs: nil, type: :user)
      @name = name.upcase
      @inputs = inputs
      @body = body
      @min_inputs = min_inputs
      @default_inputs = default_inputs
      @max_inputs = max_inputs
      @type = type
    end

    def primitive?
      @type == :primitive
    end

    def macro?
      @type == :macro
    end

    def user?
      @type == :user
    end
  end

  class Primitive < Procedure
    def initialize(name:, body:, min_inputs: 0, default_inputs: nil, max_inputs: nil)
      super(
        name: name,
        body: body,
        min_inputs: min_inputs,
        default_inputs: default_inputs || min_inputs,
        max_inputs: max_inputs,
        type: :primitive
      )
    end
  end

  class Workspace
    def initialize
      @procedures = {}   # name (upcase) => Procedure
      @buried = {}       # name => true
      @traced = {}       # name => true
      @stepped = {}      # name => true
      @plists = {}       # plistname => { propname => value }
    end

    def define(name, proc_obj)
      @procedures[name.upcase] = proc_obj
    end

    def lookup(name)
      @procedures[name.to_s.upcase]
    end

    def primitive?(name)
      p = lookup(name)
      p && p.type == :primitive
    end

    def defined?(name)
      p = lookup(name)
      p && p.type == :user
    end

    def macro?(name)
      p = lookup(name)
      p && p.type == :macro
    end

    def procedure?(name)
      !lookup(name).nil?
    end

    def erase(name)
      @procedures.delete(name.to_s.upcase)
    end

    def all_procedures
      @procedures.keys
    end

    def user_procedures
      @procedures.select { |_, v| v.user? || v.macro? }.keys
    end

    def primitive_procedures
      @procedures.select { |_, v| v.primitive? }.keys
    end

    def bury(name)
      @buried[name.to_s.upcase] = true
    end

    def unbury(name)
      @buried.delete(name.to_s.upcase)
    end

    def buried?(name)
      @buried[name.to_s.upcase] == true
    end

    def trace(name)
      @traced[name.to_s.upcase] = true
    end

    def untrace(name)
      @traced.delete(name.to_s.upcase)
    end

    def traced?(name)
      @traced[name.to_s.upcase] == true
    end

    def step(name)
      @stepped[name.to_s.upcase] = true
    end

    def unstep(name)
      @stepped.delete(name.to_s.upcase)
    end

    def stepped?(name)
      @stepped[name.to_s.upcase] == true
    end

    def pprop(plistname, propname, value)
      key = plistname.to_s.upcase
      pkey = propname.to_s.upcase
      @plists[key] ||= {}
      @plists[key][pkey] = value
    end

    def gprop(plistname, propname)
      key = plistname.to_s.upcase
      pkey = propname.to_s.upcase
      return nil unless @plists[key]
      @plists[key][pkey]
    end

    def remprop(plistname, propname)
      key = plistname.to_s.upcase
      pkey = propname.to_s.upcase
      return unless @plists[key]
      @plists[key].delete(pkey)
    end

    def plist(plistname)
      key = plistname.to_s.upcase
      return [] unless @plists[key]
      result = []
      @plists[key].each { |k, v| result << k << v }
      result
    end

    def plist_names
      @plists.keys
    end

    def all_plists
      @plists
    end

    def erase_plist(name)
      @plists.delete(name.to_s.upcase)
    end
  end
end
