module Loco
  module Primitives
    module Macros
      def register_macros
        # .MACRO - define a macro (like TO but body returns instruction list)
        # Handled as special form in workspace_management

        # .DEFMACRO
        register_primitive('.DEFMACRO', 2, 2, 2) do |interp, procname, text|
          name = interp.logo_to_word(procname).upcase
          raise LogoError, ".DEFMACRO: second input must be a list" unless text.is_a?(Array)
          proc_obj = build_procedure_from_text(interp, name, text, :macro)
          interp.workspace.define(name, proc_obj)
          nil
        end

        # MACROP / MACRO?
        register_primitive('MACROP', 1, 1, 1) do |interp, name|
          n = interp.logo_to_word(name).upcase
          interp.workspace.macro?(n) ? 'true' : 'false'
        end
        register_alias('MACRO?', 'MACROP')

        # MACROEXPAND (library)
        register_primitive('MACROEXPAND', 1, 1, 1) do |interp, expr|
          if expr.is_a?(Array) && !expr.empty?
            name = interp.logo_to_word(expr[0]).upcase
            proc_obj = interp.workspace.lookup(name)
            if proc_obj && proc_obj.macro?
              args = expr[1..]
              call_macro(interp, proc_obj, args)
            else
              expr
            end
          else
            expr
          end
        end
      end

      private

      def call_macro(interp, proc_obj, args)
        interp.env.push_frame
        begin
          proc_obj.inputs.each_with_index do |input_spec, i|
            interp.env.localmake(input_spec[:name], args[i])
          end
          result = nil
          proc_obj.body.each do |line|
            result = interp.run_list_value(line)
          end
          result
        ensure
          interp.env.pop_frame
        end
      end

      def build_procedure_from_text(interp, name, text, type = :user)
        # text is like [[inputs...] [line1] [line2] ...]
        inputs = []
        body = []
        if text.size >= 1 && text[0].is_a?(Array)
          input_list = text[0]
          input_list.each do |inp|
            if inp.is_a?(String)
              inputs << { name: inp.upcase, type: :required }
            elsif inp.is_a?(Array)
              if inp.size == 1
                inputs << { name: interp.logo_to_word(inp[0]).upcase, type: :rest }
              else
                inputs << { name: interp.logo_to_word(inp[0]).upcase, default: inp[1], type: :optional }
              end
            end
          end
          body = text[1..].map { |line| line.is_a?(Array) ? line : [line] }
        else
          body = text.map { |line| line.is_a?(Array) ? line : [line] }
        end

        required = inputs.count { |i| i[:type] == :required }
        optional = inputs.count { |i| i[:type] == :optional }
        has_rest = inputs.any? { |i| i[:type] == :rest }

        Procedure.new(
          name: name,
          inputs: inputs,
          body: body,
          min_inputs: required,
          default_inputs: required + optional,
          max_inputs: has_rest ? -1 : required + optional,
          type: type
        )
      end
    end
  end
end
