module Loco
  module Primitives
    module Logical
      def register_logical
        # AND - short-circuit evaluation, handles list inputs
        register_primitive('AND', 2, 2, -1) do |interp, *args|
          result = 'true'
          args.each do |arg|
            val = if arg.is_a?(Array)
                    interp.run_list(arg)
                    # run_list returns last value
                    interp.last_value
                  else
                    arg
                  end
            unless interp.logo_true?(val)
              result = 'false'
              break
            end
          end
          result
        end

        # OR - short-circuit evaluation
        register_primitive('OR', 2, 2, -1) do |interp, *args|
          result = 'false'
          args.each do |arg|
            val = if arg.is_a?(Array)
                    interp.run_list(arg)
                    interp.last_value
                  else
                    arg
                  end
            if interp.logo_true?(val)
              result = 'true'
              break
            end
          end
          result
        end

        # NOT
        register_primitive('NOT', 1, 1, 1) do |interp, arg|
          val = if arg.is_a?(Array)
                  interp.run_list(arg)
                  interp.last_value
                else
                  arg
                end
          interp.logo_true?(val) ? 'false' : 'true'
        end

        # BOOLEAN - convert to boolean (library helper)
        register_primitive('BOOLEAN', 1, 1, 1) do |interp, thing|
          interp.logo_true?(thing) ? 'true' : 'false'
        end
      end
    end
  end
end
