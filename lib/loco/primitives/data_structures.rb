module Loco
  module Primitives
    module DataStructures
      def register_data_structures
        # WORD
        register_primitive('WORD', 2, 2, -1) do |interp, *args|
          args.map { |a| interp.logo_to_word(a) }.join('')
        end

        # LIST
        register_primitive('LIST', 2, 2, -1) do |interp, *args|
          args.to_a
        end

        # SENTENCE / SE
        register_primitive('SENTENCE', 2, 2, -1) do |interp, *args|
          result = []
          args.each do |a|
            if a.is_a?(Array)
              result.concat(a)
            else
              result << a
            end
          end
          result
        end
        register_alias('SE', 'SENTENCE')

        # FPUT
        register_primitive('FPUT', 2, 2, 2) do |interp, thing, lst|
          if lst.is_a?(Array)
            [thing] + lst
          elsif lst.is_a?(String)
            interp.logo_to_word(thing) + lst
          else
            raise LogoError, "FPUT: second input must be a list or word"
          end
        end

        # LPUT
        register_primitive('LPUT', 2, 2, 2) do |interp, thing, lst|
          if lst.is_a?(Array)
            lst + [thing]
          elsif lst.is_a?(String)
            lst + interp.logo_to_word(thing)
          else
            raise LogoError, "LPUT: second input must be a list or word"
          end
        end

        # ARRAY
        register_primitive('ARRAY', 1, 1, 2) do |interp, size, origin = 1|
          sz = interp.to_number(size).to_i
          orig = interp.to_number(origin).to_i
          LogoArray.new(sz, orig)
        end

        # LISTTOARRAY
        register_primitive('LISTTOARRAY', 1, 1, 2) do |interp, list, origin = 1|
          raise LogoError, "LISTTOARRAY: input must be a list" unless list.is_a?(Array)
          orig = interp.to_number(origin).to_i
          LogoArray.from_array(list, orig)
        end

        # ARRAYTOLIST
        register_primitive('ARRAYTOLIST', 1, 1, 1) do |interp, arr|
          raise LogoError, "ARRAYTOLIST: input must be an array" unless arr.is_a?(LogoArray)
          arr.data.dup
        end

        # MDARRAY
        register_primitive('MDARRAY', 1, 1, 2) do |interp, sizelist, origin = 1|
          raise LogoError, "MDARRAY: first input must be a list" unless sizelist.is_a?(Array)
          orig = interp.to_number(origin).to_i
          make_mdarray(sizelist, orig)
        end

        # COMBINE
        register_primitive('COMBINE', 2, 2, 2) do |interp, thing1, thing2|
          if thing2.is_a?(Array)
            [thing1] + thing2
          else
            interp.logo_to_word(thing1) + interp.logo_to_word(thing2)
          end
        end

        # REVERSE
        register_primitive('REVERSE', 1, 1, 1) do |interp, thing|
          if thing.is_a?(Array)
            thing.reverse
          elsif thing.is_a?(String)
            thing.reverse
          elsif thing.is_a?(Numeric)
            thing.to_s.reverse
          else
            raise LogoError, "REVERSE: input must be a word or list"
          end
        end

        # GENSYM
        @gensym_counter = 0
        register_primitive('GENSYM', 0, 0, 0) do |interp|
          @gensym_counter += 1
          "G#{@gensym_counter}"
        end

        # FIRST
        register_primitive('FIRST', 1, 1, 1) do |interp, thing|
          case thing
          when Array
            raise LogoError, "FIRST: list is empty" if thing.empty?
            thing.first
          when String
            raise LogoError, "FIRST: word is empty" if thing.empty?
            thing[0]
          when Numeric
            s = interp.logo_to_s(thing)
            s[0]
          else
            raise LogoError, "FIRST: don't know how to take FIRST of #{thing.inspect}"
          end
        end

        # FIRSTS
        register_primitive('FIRSTS', 1, 1, 1) do |interp, list|
          raise LogoError, "FIRSTS: input must be a list" unless list.is_a?(Array)
          list.map do |item|
            case item
            when Array
              raise LogoError, "FIRSTS: member is empty list" if item.empty?
              item.first
            when String
              raise LogoError, "FIRSTS: member is empty word" if item.empty?
              item[0]
            when Numeric
              interp.logo_to_s(item)[0]
            end
          end
        end

        # LAST
        register_primitive('LAST', 1, 1, 1) do |interp, thing|
          case thing
          when Array
            raise LogoError, "LAST: list is empty" if thing.empty?
            thing.last
          when String
            raise LogoError, "LAST: word is empty" if thing.empty?
            thing[-1]
          when Numeric
            s = interp.logo_to_s(thing)
            s[-1]
          else
            raise LogoError, "LAST: don't know how to take LAST of #{thing.inspect}"
          end
        end

        # BUTFIRST / BF
        register_primitive('BUTFIRST', 1, 1, 1) do |interp, thing|
          case thing
          when Array
            raise LogoError, "BUTFIRST: list is empty" if thing.empty?
            thing[1..]
          when String
            raise LogoError, "BUTFIRST: word is empty" if thing.empty?
            thing[1..]
          when Numeric
            s = interp.logo_to_s(thing)
            s[1..]
          else
            raise LogoError, "BUTFIRST: invalid input"
          end
        end
        register_alias('BF', 'BUTFIRST')

        # BUTFIRSTS / BFS
        register_primitive('BUTFIRSTS', 1, 1, 1) do |interp, list|
          raise LogoError, "BUTFIRSTS: input must be a list" unless list.is_a?(Array)
          list.map do |item|
            case item
            when Array
              raise LogoError, "BUTFIRSTS: member is empty" if item.empty?
              item[1..]
            when String
              raise LogoError, "BUTFIRSTS: member is empty" if item.empty?
              item[1..]
            when Numeric
              s = interp.logo_to_s(item)
              s[1..]
            end
          end
        end
        register_alias('BFS', 'BUTFIRSTS')

        # BUTLAST / BL
        register_primitive('BUTLAST', 1, 1, 1) do |interp, thing|
          case thing
          when Array
            raise LogoError, "BUTLAST: list is empty" if thing.empty?
            thing[0...-1]
          when String
            raise LogoError, "BUTLAST: word is empty" if thing.empty?
            thing[0...-1]
          when Numeric
            s = interp.logo_to_s(thing)
            s[0...-1]
          else
            raise LogoError, "BUTLAST: invalid input"
          end
        end
        register_alias('BL', 'BUTLAST')

        # ITEM
        register_primitive('ITEM', 2, 2, 2) do |interp, index, thing|
          idx = interp.to_number(index).to_i
          case thing
          when Array
            raise LogoError, "ITEM: index #{idx} out of range" if idx < 1 || idx > thing.size
            thing[idx - 1]
          when String
            raise LogoError, "ITEM: index #{idx} out of range" if idx < 1 || idx > thing.length
            thing[idx - 1]
          when Numeric
            s = interp.logo_to_s(thing)
            raise LogoError, "ITEM: index #{idx} out of range" if idx < 1 || idx > s.length
            s[idx - 1]
          when LogoArray
            raise LogoError, "ITEM: index #{idx} out of range" if idx < thing.origin || idx > thing.origin + thing.size - 1
            thing[idx]
          else
            raise LogoError, "ITEM: don't know how to index #{thing.inspect}"
          end
        end

        # PICK
        register_primitive('PICK', 1, 1, 1) do |interp, thing|
          case thing
          when Array
            raise LogoError, "PICK: empty list" if thing.empty?
            thing.sample
          when String
            raise LogoError, "PICK: empty word" if thing.empty?
            thing[rand(thing.length)]
          else
            raise LogoError, "PICK: input must be a list or word"
          end
        end

        # REMOVE
        register_primitive('REMOVE', 2, 2, 2) do |interp, thing, lst|
          case lst
          when Array
            lst.reject { |item| interp.logo_equal?(thing, item) }
          when String
            t = interp.logo_to_word(thing)
            lst.gsub(t, '')
          else
            raise LogoError, "REMOVE: second input must be a list or word"
          end
        end

        # REMDUP
        register_primitive('REMDUP', 1, 1, 1) do |interp, lst|
          raise LogoError, "REMDUP: input must be a list" unless lst.is_a?(Array)
          # Keep rightmost occurrence
          seen = []
          lst.reverse.each do |item|
            seen << item unless seen.any? { |s| interp.logo_equal?(s, item) }
          end
          seen.reverse
        end

        # QUOTED
        register_primitive('QUOTED', 1, 1, 1) do |interp, thing|
          interp.logo_to_word(thing)
        end

        # SETITEM
        register_primitive('SETITEM', 3, 3, 3) do |interp, index, arr, value|
          raise LogoError, "SETITEM: second input must be an array" unless arr.is_a?(LogoArray)
          idx = interp.to_number(index).to_i
          raise LogoError, "SETITEM: index #{idx} out of range" if idx < arr.origin || idx > arr.origin + arr.size - 1
          # Check circularity
          raise LogoError, "SETITEM: circular array" if value.equal?(arr)
          arr[idx] = value
          nil
        end

        # .SETFIRST
        register_primitive('.SETFIRST', 2, 2, 2) do |interp, lst, value|
          raise LogoError, ".SETFIRST: first input must be a list" unless lst.is_a?(Array)
          raise LogoError, ".SETFIRST: list is empty" if lst.empty?
          lst[0] = value
          nil
        end

        # .SETBF
        register_primitive('.SETBF', 2, 2, 2) do |interp, lst, value|
          raise LogoError, ".SETBF: first input must be a list" unless lst.is_a?(Array)
          raise LogoError, ".SETBF: value must be a list" unless value.is_a?(Array)
          lst.replace([lst[0]] + value)
          nil
        end

        # .SETITEM
        register_primitive('.SETITEM', 3, 3, 3) do |interp, index, arr, value|
          raise LogoError, ".SETITEM: second input must be an array" unless arr.is_a?(LogoArray)
          idx = interp.to_number(index).to_i
          arr[idx] = value
          nil
        end

        # PUSH
        register_primitive('PUSH', 2, 2, 2) do |interp, stackname, thing|
          name = interp.logo_to_word(stackname)
          lst = interp.env.defined?(name) ? interp.env.thing(name) : []
          raise LogoError, "PUSH: #{name} must be a list" unless lst.is_a?(Array)
          interp.env.make(name, [thing] + lst)
          nil
        end

        # POP
        register_primitive('POP', 1, 1, 1) do |interp, stackname|
          name = interp.logo_to_word(stackname)
          lst = interp.env.thing(name)
          raise LogoError, "POP: #{name} must be a non-empty list" unless lst.is_a?(Array) && !lst.empty?
          val = lst.first
          interp.env.make(name, lst[1..])
          val
        end

        # QUEUE
        register_primitive('QUEUE', 2, 2, 2) do |interp, qname, thing|
          name = interp.logo_to_word(qname)
          lst = interp.env.defined?(name) ? interp.env.thing(name) : []
          raise LogoError, "QUEUE: #{name} must be a list" unless lst.is_a?(Array)
          interp.env.make(name, lst + [thing])
          nil
        end

        # DEQUEUE
        register_primitive('DEQUEUE', 1, 1, 1) do |interp, qname|
          name = interp.logo_to_word(qname)
          lst = interp.env.thing(name)
          raise LogoError, "DEQUEUE: #{name} must be a non-empty list" unless lst.is_a?(Array) && !lst.empty?
          val = lst.first
          interp.env.make(name, lst[1..])
          val
        end

        # WORDP / WORD?
        register_primitive('WORDP', 1, 1, 1) do |interp, thing|
          (thing.is_a?(String) || thing.is_a?(Numeric)) ? 'true' : 'false'
        end
        register_alias('WORD?', 'WORDP')

        # LISTP / LIST?
        register_primitive('LISTP', 1, 1, 1) do |interp, thing|
          thing.is_a?(Array) ? 'true' : 'false'
        end
        register_alias('LIST?', 'LISTP')

        # ARRAYP / ARRAY?
        register_primitive('ARRAYP', 1, 1, 1) do |interp, thing|
          thing.is_a?(LogoArray) ? 'true' : 'false'
        end
        register_alias('ARRAY?', 'ARRAYP')

        # EMPTYP / EMPTY?
        register_primitive('EMPTYP', 1, 1, 1) do |interp, thing|
          result = case thing
                   when Array then thing.empty?
                   when String then thing.empty?
                   when Numeric then thing.to_s.empty?
                   else false
                   end
          result ? 'true' : 'false'
        end
        register_alias('EMPTY?', 'EMPTYP')

        # EQUALP / EQUAL? / = (handled as infix too)
        register_primitive('EQUALP', 2, 2, 2) do |interp, a, b|
          interp.logo_equal?(a, b) ? 'true' : 'false'
        end
        register_alias('EQUAL?', 'EQUALP')

        # NOTEQUALP / NOTEQUAL?
        register_primitive('NOTEQUALP', 2, 2, 2) do |interp, a, b|
          interp.logo_equal?(a, b) ? 'false' : 'true'
        end
        register_alias('NOTEQUAL?', 'NOTEQUALP')

        # BEFOREP / BEFORE?
        register_primitive('BEFOREP', 2, 2, 2) do |interp, w1, w2|
          s1 = interp.logo_to_word(w1)
          s2 = interp.logo_to_word(w2)
          (s1 < s2) ? 'true' : 'false'
        end
        register_alias('BEFORE?', 'BEFOREP')

        # .EQ
        register_primitive('.EQ', 2, 2, 2) do |interp, a, b|
          a.equal?(b) ? 'true' : 'false'
        end

        # MEMBERP / MEMBER?
        register_primitive('MEMBERP', 2, 2, 2) do |interp, thing, container|
          result = case container
                   when Array
                     container.any? { |item| interp.logo_equal?(item, thing) }
                   when String
                     t = interp.logo_to_word(thing)
                     container.include?(t)
                   else
                     false
                   end
          result ? 'true' : 'false'
        end
        register_alias('MEMBER?', 'MEMBERP')

        # SUBSTRINGP / SUBSTRING?
        register_primitive('SUBSTRINGP', 2, 2, 2) do |interp, thing1, thing2|
          s1 = interp.logo_to_word(thing1)
          s2 = interp.logo_to_word(thing2)
          s2.include?(s1) ? 'true' : 'false'
        end
        register_alias('SUBSTRING?', 'SUBSTRINGP')

        # NUMBERP / NUMBER?
        register_primitive('NUMBERP', 1, 1, 1) do |interp, thing|
          case thing
          when Numeric then 'true'
          when String
            thing =~ /\A-?[0-9]+(\.[0-9]+)?([eE][+\-]?[0-9]+)?\z/ ? 'true' : 'false'
          else
            'false'
          end
        end
        register_alias('NUMBER?', 'NUMBERP')

        # VBARREDP / VBARRED?
        register_primitive('VBARREDP', 1, 1, 1) do |interp, char|
          'false'
        end
        register_alias('VBARRED?', 'VBARREDP')

        # BACKSLASHEDP / BACKSLASHED?
        register_primitive('BACKSLASHEDP', 1, 1, 1) do |interp, char|
          'false'
        end
        register_alias('BACKSLASHED?', 'BACKSLASHEDP')

        # COUNT
        register_primitive('COUNT', 1, 1, 1) do |interp, thing|
          case thing
          when Array then thing.size
          when String then thing.length
          when Numeric then interp.logo_to_s(thing).length
          when LogoArray then thing.size
          else
            raise LogoError, "COUNT: don't know how to count #{thing.inspect}"
          end
        end

        # ASCII
        register_primitive('ASCII', 1, 1, 1) do |interp, char|
          s = interp.logo_to_word(char)
          raise LogoError, "ASCII: input must be a single character" if s.empty?
          s[0].ord
        end

        # RAWASCII
        register_primitive('RAWASCII', 1, 1, 1) do |interp, char|
          s = interp.logo_to_word(char)
          raise LogoError, "RAWASCII: input must be a single character" if s.empty?
          s[0].ord
        end

        # CHAR
        register_primitive('CHAR', 1, 1, 1) do |interp, num|
          interp.to_number(num).to_i.chr
        end

        # MEMBER
        register_primitive('MEMBER', 2, 2, 2) do |interp, thing, container|
          case container
          when Array
            idx = container.index { |item| interp.logo_equal?(item, thing) }
            idx ? container[idx..] : []
          when String
            t = interp.logo_to_word(thing)
            idx = container.index(t)
            idx ? container[idx..] : ''
          else
            raise LogoError, "MEMBER: second input must be a list or word"
          end
        end

        # LOWERCASE
        register_primitive('LOWERCASE', 1, 1, 1) do |interp, word|
          interp.logo_to_word(word).downcase
        end

        # UPPERCASE
        register_primitive('UPPERCASE', 1, 1, 1) do |interp, word|
          interp.logo_to_word(word).upcase
        end

        # STANDOUT
        register_primitive('STANDOUT', 1, 1, 1) do |interp, thing|
          thing
        end

        # PARSE
        register_primitive('PARSE', 1, 1, 1) do |interp, word|
          s = interp.logo_to_word(word)
          tokens = Tokenizer.new(s).tokenize
          stream = TokenStream.new(tokens)
          result = []
          until stream.empty?
            result << interp.eval_expr(stream)
          end
          result
        end

        # RUNPARSE
        register_primitive('RUNPARSE', 1, 1, 1) do |interp, thing|
          s = thing.is_a?(Array) ? thing.map { |m| interp.logo_to_s(m) }.join(' ') : interp.logo_to_word(thing)
          tokens = Tokenizer.new(s).tokenize
          stream = TokenStream.new(tokens)
          result = []
          until stream.empty?
            tok = stream.consume
            result << case tok.type
                       when :number then tok.value
                       when :word then tok.value
                       when :name then tok.value
                       when :infix_op then tok.value
                       when :left_bracket then '['
                       when :right_bracket then ']'
                       else tok.value.to_s
                       end
          end
          result
        end

        # MDITEM
        register_primitive('MDITEM', 2, 2, 2) do |interp, indexlist, arr|
          raise LogoError, "MDITEM: first input must be a list" unless indexlist.is_a?(Array)
          raise LogoError, "MDITEM: second input must be an array" unless arr.is_a?(LogoArray)
          current = arr
          indexlist.each do |idx|
            raise LogoError, "MDITEM: intermediate element must be an array" unless current.is_a?(LogoArray)
            current = current[interp.to_number(idx).to_i]
          end
          current
        end

        # MDSETITEM
        register_primitive('MDSETITEM', 3, 3, 3) do |interp, indexlist, arr, value|
          raise LogoError, "MDSETITEM: first input must be a list" unless indexlist.is_a?(Array)
          raise LogoError, "MDSETITEM: second input must be an array" unless arr.is_a?(LogoArray)
          *prefix, last = indexlist.map { |i| interp.to_number(i).to_i }
          current = arr
          prefix.each do |idx|
            current = current[idx]
            raise LogoError, "MDSETITEM: intermediate element must be an array" unless current.is_a?(LogoArray)
          end
          current[last] = value
          nil
        end
      end

      private

      def make_mdarray(sizelist, origin)
        size = @interp_ref.to_number(sizelist.first).to_i
        arr = LogoArray.new(size, origin)
        if sizelist.size > 1
          rest = sizelist[1..]
          size.times do |i|
            arr.data[i] = make_mdarray(rest, origin)
          end
        end
        arr
      end
    end
  end
end
