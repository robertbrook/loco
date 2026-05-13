module Loco
  module Primitives
    module Control
      def register_control
        # RUN
        register_primitive('RUN', 1, 1, 1) do |interp, list|
          raise LogoError, "RUN: input must be a list" unless list.is_a?(Array)
          interp.run_list(list)
        end

        # RUNRESULT
        register_primitive('RUNRESULT', 1, 1, 1) do |interp, list|
          raise LogoError, "RUNRESULT: input must be a list" unless list.is_a?(Array)
          begin
            result = interp.run_list(list)
            result.nil? ? [] : [result]
          rescue OutputSignal => e
            [e.value]
          end
        end

        # REPEAT
        register_primitive('REPEAT', 2, 2, 2) do |interp, num, list|
          n = interp.to_number(num).to_i
          raise LogoError, "REPEAT: first input must be a list" unless list.is_a?(Array)
          interp.repcount_stack.push(0)
          begin
            n.times do |i|
              interp.repcount_stack[-1] = i + 1
              interp.run_list(list)
            end
          rescue ThrowSignal => e
            raise unless e.tag == 'STOP'
          ensure
            interp.repcount_stack.pop
          end
          nil
        end

        # FOREVER
        register_primitive('FOREVER', 1, 1, 1) do |interp, list|
          raise LogoError, "FOREVER: input must be a list" unless list.is_a?(Array)
          interp.repcount_stack.push(0)
          begin
            loop do
              interp.repcount_stack[-1] += 1
              interp.run_list(list)
            end
          rescue ThrowSignal => e
            raise unless e.tag == 'STOP'
          rescue StopSignal
            # stop
          ensure
            interp.repcount_stack.pop
          end
          nil
        end

        # REPCOUNT
        register_primitive('REPCOUNT', 0, 0, 0) do |interp|
          interp.repcount_stack.last || -1
        end

        # IF
        register_primitive('IF', 2, 2, 3) do |interp, tf, list1, list2 = nil|
          if interp.logo_true?(tf)
            raise LogoError, "IF: second input must be a list" unless list1.is_a?(Array)
            interp.run_list(list1)
          elsif list2
            raise LogoError, "IF: third input must be a list" unless list2.is_a?(Array)
            interp.run_list(list2)
          end
          nil
        end

        # IFELSE
        register_primitive('IFELSE', 3, 3, 3) do |interp, tf, list1, list2|
          raise LogoError, "IFELSE: second input must be a list" unless list1.is_a?(Array)
          raise LogoError, "IFELSE: third input must be a list" unless list2.is_a?(Array)
          if interp.logo_true?(tf)
            interp.run_list(list1)
          else
            interp.run_list(list2)
          end
        end

        # TEST
        register_primitive('TEST', 1, 1, 1) do |interp, tf|
          interp.test_flag = interp.logo_true?(tf)
          nil
        end

        # IFTRUE / IFT
        register_primitive('IFTRUE', 1, 1, 1) do |interp, list|
          raise LogoError, "IFTRUE: TEST not yet run" if interp.test_flag.nil?
          raise LogoError, "IFTRUE: input must be a list" unless list.is_a?(Array)
          interp.run_list(list) if interp.test_flag
          nil
        end
        register_alias('IFT', 'IFTRUE')

        # IFFALSE / IFF
        register_primitive('IFFALSE', 1, 1, 1) do |interp, list|
          raise LogoError, "IFFALSE: TEST not yet run" if interp.test_flag.nil?
          raise LogoError, "IFFALSE: input must be a list" unless list.is_a?(Array)
          interp.run_list(list) unless interp.test_flag
          nil
        end
        register_alias('IFF', 'IFFALSE')

        # STOP
        register_primitive('STOP', 0, 0, 0) do |interp|
          raise StopSignal
        end

        # OUTPUT / OP
        register_primitive('OUTPUT', 1, 1, 1) do |interp, val|
          raise OutputSignal.new(val)
        end
        register_alias('OP', 'OUTPUT')

        # .MAYBEOUTPUT
        register_primitive('.MAYBEOUTPUT', 1, 1, 1) do |interp, val|
          raise OutputSignal.new(val) unless val.nil?
          nil
        end

        # CATCH
        register_primitive('CATCH', 2, 2, 2) do |interp, tag, list|
          t = interp.logo_to_word(tag).upcase
          raise LogoError, "CATCH: second input must be a list" unless list.is_a?(Array)
          begin
            interp.run_list(list)
          rescue ThrowSignal => e
            raise unless e.tag == t || t == 'ERROR'
            e.value
          rescue LogoError => e
            raise unless t == 'ERROR'
            interp.last_error = e
            nil
          end
        end

        # THROW
        register_primitive('THROW', 1, 1, 2) do |interp, tag, value = nil|
          t = interp.logo_to_word(tag)
          raise ThrowSignal.new(t, value)
        end

        # ERROR
        register_primitive('ERROR', 0, 0, 0) do |interp|
          err = interp.last_error
          return [] unless err
          [err.class.name, err.message, 'unknown', -1]
        end

        # PAUSE
        register_primitive('PAUSE', 0, 0, 0) do |interp|
          raise PauseSignal
        end

        # CONTINUE / CO
        register_primitive('CONTINUE', 0, 0, 1) do |interp, val = nil|
          # Handled specially by REPL
          interp.continue_value = val
          raise ThrowSignal.new('PAUSE', val)
        end
        register_alias('CO', 'CONTINUE')

        # WAIT
        register_primitive('WAIT', 1, 1, 1) do |interp, ticks|
          secs = interp.to_number(ticks).to_f / 60.0
          sleep(secs)
          nil
        end

        # BYE
        register_primitive('BYE', 0, 0, 0) do |interp|
          exit(0)
        end

        # GOTO
        register_primitive('GOTO', 1, 1, 1) do |interp, tag|
          t = interp.logo_to_word(tag)
          raise GotoSignal.new(t)
        end

        # TAG - does nothing at runtime, marker only
        register_primitive('TAG', 1, 1, 1) do |interp, tag|
          nil
        end

        # IGNORE
        register_primitive('IGNORE', 1, 1, 1) do |interp, val|
          nil
        end

        # FOR loop (library)
        register_primitive('FOR', 2, 2, 2) do |interp, control, list|
          raise LogoError, "FOR: first input must be a list" unless control.is_a?(Array)
          raise LogoError, "FOR: first input must have at least 3 elements" unless control.size >= 3
          raise LogoError, "FOR: second input must be a list" unless list.is_a?(Array)

          var = interp.logo_to_word(control[0])
          from = interp.to_number(control[1]).to_f
          to_val = interp.to_number(control[2]).to_f
          step = control.size >= 4 ? interp.to_number(control[3]).to_f : (from <= to_val ? 1.0 : -1.0)

          interp.env.push_frame
          begin
            i = from
            loop do
              break if step > 0 && i > to_val
              break if step < 0 && i < to_val
              break if step == 0
              val = i == i.to_i ? i.to_i : i
              interp.env.localmake(var, val)
              interp.run_list(list)
              i += step
            end
          rescue ThrowSignal => e
            raise unless e.tag == 'STOP'
          rescue StopSignal
            # stop
          ensure
            interp.env.pop_frame
          end
          nil
        end

        # WHILE
        register_primitive('WHILE', 2, 2, 2) do |interp, tfexpr, list|
          raise LogoError, "WHILE: second input must be a list" unless list.is_a?(Array)
          begin
            loop do
              cond = if tfexpr.is_a?(Array)
                       interp.run_list_value(tfexpr)
                     else
                       tfexpr
                     end
              break unless interp.logo_true?(cond)
              interp.run_list(list)
            end
          rescue ThrowSignal => e
            raise unless e.tag == 'STOP'
          rescue StopSignal
            # stop
          end
          nil
        end

        # UNTIL
        register_primitive('UNTIL', 2, 2, 2) do |interp, tfexpr, list|
          raise LogoError, "UNTIL: second input must be a list" unless list.is_a?(Array)
          begin
            loop do
              cond = if tfexpr.is_a?(Array)
                       interp.run_list_value(tfexpr)
                     else
                       tfexpr
                     end
              break if interp.logo_true?(cond)
              interp.run_list(list)
            end
          rescue ThrowSignal => e
            raise unless e.tag == 'STOP'
          rescue StopSignal
            # stop
          end
          nil
        end

        # DO.WHILE
        register_primitive('DO.WHILE', 2, 2, 2) do |interp, list, tfexpr|
          raise LogoError, "DO.WHILE: first input must be a list" unless list.is_a?(Array)
          begin
            loop do
              interp.run_list(list)
              cond = if tfexpr.is_a?(Array)
                       interp.run_list_value(tfexpr)
                     else
                       tfexpr
                     end
              break unless interp.logo_true?(cond)
            end
          rescue ThrowSignal => e
            raise unless e.tag == 'STOP'
          rescue StopSignal
            # stop
          end
          nil
        end

        # DO.UNTIL
        register_primitive('DO.UNTIL', 2, 2, 2) do |interp, list, tfexpr|
          raise LogoError, "DO.UNTIL: first input must be a list" unless list.is_a?(Array)
          begin
            loop do
              interp.run_list(list)
              cond = if tfexpr.is_a?(Array)
                       interp.run_list_value(tfexpr)
                     else
                       tfexpr
                     end
              break if interp.logo_true?(cond)
            end
          rescue ThrowSignal => e
            raise unless e.tag == 'STOP'
          rescue StopSignal
            # stop
          end
          nil
        end

        # CASE
        register_primitive('CASE', 2, 2, 2) do |interp, value, clauses|
          raise LogoError, "CASE: second input must be a list" unless clauses.is_a?(Array)
          found = nil
          clauses.each do |clause|
            raise LogoError, "CASE: each clause must be a list" unless clause.is_a?(Array)
            raise LogoError, "CASE: clause must have at least 2 elements" unless clause.size >= 2
            conditions = clause[0]
            body = clause[1..]
            if conditions == 'ELSE' || conditions.to_s.upcase == 'ELSE'
              found = body
              break
            end
            raise LogoError, "CASE: first element of clause must be a list" unless conditions.is_a?(Array)
            if conditions.any? { |c| interp.logo_equal?(c, value) }
              found = body
              break
            end
          end
          if found
            interp.run_list(found.size == 1 ? found[0] : found)
          end
          nil
        end

        # COND
        register_primitive('COND', 1, 1, 1) do |interp, clauses|
          raise LogoError, "COND: input must be a list" unless clauses.is_a?(Array)
          found = nil
          clauses.each do |clause|
            raise LogoError, "COND: each clause must be a list" unless clause.is_a?(Array)
            raise LogoError, "COND: clause must have at least 2 elements" unless clause.size >= 2
            condition = clause[0]
            body = clause[1..]
            if condition == 'ELSE' || condition.to_s.upcase == 'ELSE'
              found = body
              break
            end
            cond_val = if condition.is_a?(Array)
                         interp.run_list_value(condition)
                       else
                         condition
                       end
            if interp.logo_true?(cond_val)
              found = body
              break
            end
          end
          if found
            interp.run_list(found.size == 1 ? found[0] : found)
          end
          nil
        end
      end
    end
  end
end
