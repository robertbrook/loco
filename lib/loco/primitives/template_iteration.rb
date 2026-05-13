module Loco
  module Primitives
    module TemplateIteration
      def register_template_iteration
        # APPLY
        register_primitive('APPLY', 2, 2, 2) do |interp, template, inputlist|
          raise LogoError, "APPLY: second input must be a list" unless inputlist.is_a?(Array)
          apply_template(interp, template, inputlist)
        end

        # INVOKE (library)
        register_primitive('INVOKE', 1, 1, -1) do |interp, template, *inputs|
          apply_template(interp, template, inputs)
        end

        # MAP
        register_primitive('MAP', 2, 2, -1) do |interp, template, *data_lists|
          raise LogoError, "MAP: need at least one data list" if data_lists.empty?
          data_lists.each do |dl|
            raise LogoError, "MAP: data inputs must be lists or words" unless dl.is_a?(Array) || dl.is_a?(String)
          end
          size = data_lists[0].is_a?(Array) ? data_lists[0].size : data_lists[0].length
          result = []
          size.times do |i|
            slot_values = data_lists.map { |dl| dl.is_a?(Array) ? dl[i] : dl[i].to_s }
            val = apply_template_with_index(interp, template, slot_values, i + 1)
            result << val unless val.nil?
          end
          result
        end

        # MAP.SE
        register_primitive('MAP.SE', 2, 2, -1) do |interp, template, *data_lists|
          raise LogoError, "MAP.SE: need at least one data list" if data_lists.empty?
          size = data_lists[0].is_a?(Array) ? data_lists[0].size : data_lists[0].length
          result = []
          size.times do |i|
            slot_values = data_lists.map { |dl| dl.is_a?(Array) ? dl[i] : dl[i].to_s }
            val = apply_template_with_index(interp, template, slot_values, i + 1)
            case val
            when Array then result.concat(val)
            when nil then # skip
            else result << val
            end
          end
          result
        end

        # FOREACH (library)
        register_primitive('FOREACH', 2, 2, -1) do |interp, *args|
          template = args.last
          data_lists = args[0...-1]
          raise LogoError, "FOREACH: need at least one data list" if data_lists.empty?
          size = data_lists[0].is_a?(Array) ? data_lists[0].size : data_lists[0].length
          size.times do |i|
            slot_values = data_lists.map { |dl| dl.is_a?(Array) ? dl[i] : dl[i].to_s }
            apply_template_with_index(interp, template, slot_values, i + 1)
          end
          nil
        end

        # FILTER
        register_primitive('FILTER', 2, 2, 2) do |interp, template, data|
          case data
          when Array
            data.select.with_index(1) do |item, idx|
              val = apply_template_with_index(interp, template, [item], idx)
              interp.logo_true?(val)
            end
          when String
            data.chars.select.with_index(1) do |ch, idx|
              val = apply_template_with_index(interp, template, [ch], idx)
              interp.logo_true?(val)
            end.join
          else
            raise LogoError, "FILTER: second input must be a list or word"
          end
        end

        # FIND
        register_primitive('FIND', 2, 2, 2) do |interp, template, data|
          raise LogoError, "FIND: second input must be a list or word" unless data.is_a?(Array) || data.is_a?(String)
          items = data.is_a?(Array) ? data : data.chars
          items.each_with_index do |item, idx|
            val = apply_template_with_index(interp, template, [item], idx + 1)
            return item if interp.logo_true?(val)
          end
          []
        end

        # REDUCE
        register_primitive('REDUCE', 2, 2, 2) do |interp, template, data|
          raise LogoError, "REDUCE: second input must be a list" unless data.is_a?(Array)
          raise LogoError, "REDUCE: list must have at least one element" if data.empty?
          data[1..].reduce(data[0]) do |acc, item|
            apply_template(interp, template, [acc, item])
          end
        end

        # CROSSMAP
        register_primitive('CROSSMAP', 2, 2, -1) do |interp, template, *data_lists|
          raise LogoError, "CROSSMAP: need at least one data list" if data_lists.empty?
          # Single list of lists
          if data_lists.size == 1 && data_lists[0].is_a?(Array) && data_lists[0].all? { |e| e.is_a?(Array) }
            data_lists = data_lists[0]
          end
          cross_product = data_lists.reduce([[]]){ |acc, arr| acc.product(arr).map(&:flatten) }
          cross_product.map do |inputs|
            apply_template(interp, template, inputs)
          end
        end

        # CASCADE
        register_primitive('CASCADE', 3, 3, -1) do |interp, *args|
          endtest = args[0]
          startvalues_and_templates = args[1..]
          # Interleaved: template1, startval1, template2, startval2, ...
          # or endtest template startvalue
          if args.size == 3
            endtest, template, startval = args
            current = startval
            count = 0
            loop do
              count += 1
              test_val = apply_template_with_index(interp, endtest, [current], count)
              break if interp.logo_true?(test_val)
              current = apply_template_with_index(interp, template, [current], count)
            end
            current
          else
            raise LogoError, "CASCADE: unexpected argument count"
          end
        end

        # CASCADE.2
        register_primitive('CASCADE.2', 6, 6, 6) do |interp, endtest, tmp1, sv1, tmp2, sv2, dummy = nil|
          cur1 = sv1
          cur2 = sv2
          count = 0
          loop do
            count += 1
            test_val = apply_template_with_index(interp, endtest, [cur1, cur2], count)
            break if interp.logo_true?(test_val)
            new1 = apply_template_with_index(interp, tmp1, [cur1, cur2], count)
            new2 = apply_template_with_index(interp, tmp2, [cur1, cur2], count)
            cur1 = new1
            cur2 = new2
          end
          [cur1, cur2]
        end

        # TRANSFER
        register_primitive('TRANSFER', 3, 3, 3) do |interp, endtest, template, inbasket|
          raise LogoError, "TRANSFER: third input must be a list" unless inbasket.is_a?(Array)
          outbasket = []
          count = 0
          remaining = inbasket.dup
          loop do
            count += 1
            test_val = apply_template_with_index(interp, endtest, [remaining], count)
            break if interp.logo_true?(test_val)
            val = apply_template_with_index(interp, template, [remaining], count)
            outbasket << val unless val.nil?
            remaining = remaining[1..] || []
          end
          outbasket
        end
      end

      private

      def apply_template(interp, template, inputs)
        apply_template_with_index(interp, template, inputs, nil)
      end

      def apply_template_with_index(interp, template, inputs, index)
        case template
        when String
          # Named procedure
          proc_obj = interp.workspace.lookup(template.upcase)
          raise LogoError, "APPLY: unknown procedure #{template}" unless proc_obj
          interp.call_procedure(proc_obj, inputs)
        when Array
          if template.size >= 1 && template[0].is_a?(Array)
            # Named-slot template: [[x y] body] or [[x y] [body1] [body2]]
            param_list = template[0]
            bodies = template[1..]
            interp.env.push_frame
            begin
              param_list.each_with_index do |param, i|
                pname = interp.logo_to_word(param)
                interp.env.localmake(pname, inputs[i])
              end
              result = nil
              bodies.each do |body|
                if body.is_a?(Array)
                  result = interp.run_list_value(body)
                else
                  result = body
                end
              end
              result
            ensure
              interp.env.pop_frame
            end
          else
            # Explicit-slot template: [? + 1] or [?1 + ?2]
            run_slot_template(interp, template, inputs, index)
          end
        else
          raise LogoError, "APPLY: template must be a list or word"
        end
      end

      def run_slot_template(interp, template, inputs, index)
        # Replace ? with inputs[0], ?1 with inputs[0], ?2 with inputs[1], etc.
        # Then run the resulting list
        substituted = substitute_slots(template, inputs, index)
        interp.run_list_value(substituted)
      end

      def substitute_slots(template, inputs, index)
        template.map do |item|
          case item
          when '?', :"?"
            inputs[0]
          when /\A\?REST\z/i
            inputs[1..]
          when /\A\?(\d+)\z/
            idx = $1.to_i - 1
            inputs[idx]
          when '#'
            index
          when Array
            substitute_slots(item, inputs, index)
          else
            item
          end
        end
      end
    end
  end
end
