require 'set'
require_relative 'errors'
require_relative 'token'
require_relative 'tokenizer'
require_relative 'logo_array'
require_relative 'environment'
require_relative 'workspace'
require_relative 'primitives/data_structures'
require_relative 'primitives/communication'
require_relative 'primitives/file_access'
require_relative 'primitives/arithmetic'
require_relative 'primitives/logical'
require_relative 'primitives/control'
require_relative 'primitives/template_iteration'
require_relative 'primitives/macros'
require_relative 'primitives/workspace_management'

module Loco
  class Interpreter
    include Primitives::DataStructures
    include Primitives::Communication
    include Primitives::FileAccess
    include Primitives::Arithmetic
    include Primitives::Logical
    include Primitives::Control
    include Primitives::TemplateIteration
    include Primitives::Macros
    include Primitives::WorkspaceManagement

    attr_reader :workspace, :env
    attr_accessor :repcount_stack, :test_flag, :last_error, :last_value
    attr_accessor :file_prefix, :open_files, :dribble_file
    attr_accessor :read_stream, :write_stream
    attr_accessor :lib_loc, :help_loc, :continue_value

    OP_PRECEDENCE = {
      '*'  => 3,
      '/'  => 3,
      '+'  => 2,
      '-'  => 2,
      '='  => 1,
      '<>' => 1,
      '<'  => 1,
      '>'  => 1,
      '<=' => 1,
      '>=' => 1
    }.freeze

    def initialize
      @workspace = Workspace.new
      @env = Environment.new
      @repcount_stack = []
      @test_flag = nil
      @last_error = nil
      @last_value = nil
      @file_prefix = ''
      @open_files = {}
      @dribble_file = nil
      @read_stream = nil
      @write_stream = nil
      @lib_loc = nil
      @help_loc = nil
      @gensym_counter = 0
      @continue_value = nil
      @in_paren = false

      register_all_primitives
    end

    def register_all_primitives
      register_data_structures
      register_communication
      register_file_access
      register_arithmetic
      register_logical
      register_control
      register_template_iteration
      register_macros
      register_workspace_management

      # Set up CASEIGNOREDP default
      @env.global_set('CASEIGNOREDP', 'true')
    end

    def register_primitive(name, min_inputs, default_inputs, max_inputs, &block)
      @workspace.define(name.upcase, Primitive.new(
        name: name.upcase,
        min_inputs: min_inputs,
        default_inputs: [default_inputs, min_inputs].max,
        max_inputs: max_inputs == -1 ? nil : max_inputs,
        body: block
      ))
    end

    def register_alias(alias_name, target_name)
      target = @workspace.lookup(target_name.upcase)
      raise "No procedure #{target_name} to alias" unless target
      @workspace.define(alias_name.upcase, target)
    end

    # Run a string of Logo code
    def run(source)
      tokens = Tokenizer.new(source).tokenize
      stream = TokenStream.new(tokens)
      run_stream(stream)
    end

    # Evaluate a single expression from a string, return result
    def eval_str(source)
      tokens = Tokenizer.new(source).tokenize
      stream = TokenStream.new(tokens)
      eval_expr(stream)
    end

    # Run instructions from a TokenStream
    def run_stream(stream)
      result = nil
      until stream.empty?
        val = eval_expr(stream)
        unless val.nil?
          @last_value = val
          # In top-level, warn about unused values but don't crash
        end
        result = val
      end
      result
    end

    # Evaluate one expression (primary + optional infix chain)
    def eval_expr(stream, min_prec = 0)
      left = eval_primary(stream)
      while (tok = stream.peek) && tok.type == :infix_op
        prec = OP_PRECEDENCE[tok.value] || 0
        break if prec < min_prec
        op = stream.consume.value
        right_prec = prec + 1  # left-associative
        right = eval_expr(stream, right_prec)
        left = apply_infix(op, left, right)
      end
      left
    end

    # Evaluate one primary expression
    def eval_primary(stream)
      # Skip newlines between expressions
      stream.skip_newlines
      return nil if stream.empty?
      tok = stream.peek

      case tok.type
      when :number
        stream.consume
        tok.value
      when :word
        stream.consume
        tok.value
      when :variable
        stream.consume
        @env.thing(tok.value)
      when :left_bracket
        collect_list(stream)
      when :left_brace
        collect_array(stream)
      when :left_paren
        eval_paren(stream)
      when :infix_op
        if tok.value == '-'
          stream.consume
          val = eval_primary(stream)
          -to_number(val)
        else
          raise LogoError, "Unexpected operator: #{tok.value}"
        end
      when :name
        name = tok.value.upcase
        if name == 'MINUS' || name == '-'
          stream.consume
          val = eval_primary(stream)
          -to_number(val)
        else
          stream.consume
          call_proc(name, stream)
        end
      when :right_bracket, :right_paren, :right_brace, :newline
        nil
      else
        stream.consume
        tok.value
      end
    end

    # Collect a list literal from the token stream
    def collect_list(stream)
      raise LogoError, "Expected '['" unless stream.peek&.type == :left_bracket
      stream.consume  # consume [
      result = []
      depth = 1
      until stream.empty?
        tok = stream.peek
        if tok.type == :newline
          stream.consume  # newlines inside lists are whitespace
        elsif tok.type == :left_bracket
          depth += 1
          stream.consume
          result << collect_sublist_tokens(stream, depth - 1)
          depth -= 1
        elsif tok.type == :right_bracket
          stream.consume
          depth -= 1
          break if depth == 0
        else
          stream.consume
          result << token_to_logo_value(tok)
        end
      end
      result
    end

    def collect_sublist_tokens(stream, depth)
      result = []
      until stream.empty?
        tok = stream.peek
        if tok.type == :newline
          stream.consume  # skip newlines inside lists
        elsif tok.type == :left_bracket
          stream.consume
          result << collect_sublist_tokens(stream, depth + 1)
        elsif tok.type == :right_bracket
          stream.consume
          break
        else
          stream.consume
          result << token_to_logo_value(tok)
        end
      end
      result
    end

    def token_to_logo_value(tok)
      case tok.type
      when :number then tok.value
      when :word then '"' + tok.value  # preserve quoting for round-trip serialization
      when :name then tok.value
      when :variable then ":#{tok.value}"
      when :infix_op then tok.value
      when :left_bracket then '['
      when :right_bracket then ']'
      when :left_paren then '('
      when :right_paren then ')'
      else tok.value.to_s
      end
    end

    # Collect an array literal from the token stream
    def collect_array(stream)
      raise LogoError, "Expected '{'" unless stream.peek&.type == :left_brace
      stream.consume  # consume {

      # Check for optional origin specifier at end: {a b c}@2
      elements = []
      until stream.empty?
        tok = stream.peek
        break if tok.type == :right_brace
        elements << eval_expr(stream)
      end
      stream.consume if stream.peek&.type == :right_brace  # consume }

      origin = 1
      # Check for @N after brace
      if stream.peek && stream.peek.type == :infix_op && stream.peek.value == '@'
        stream.consume
        origin = to_number(eval_primary(stream)).to_i
      end

      LogoArray.from_array(elements, origin)
    end

    # Handle parenthesized expressions or procedure calls
    def eval_paren(stream)
      stream.consume  # consume (
      stream.skip_newlines

      # Check if next token is a procedure name
      if stream.peek && stream.peek.type == :name
        name = stream.peek.value.upcase
        proc_obj = @workspace.lookup(name)
        if proc_obj
          stream.consume  # consume proc name
          # Read args until )
          args = []
          loop do
            stream.skip_newlines
            break if stream.empty? || stream.peek&.type == :right_paren
            args << eval_expr(stream)
          end
          stream.consume if stream.peek&.type == :right_paren  # consume )
          return call_procedure(proc_obj, args)
        end
      end

      # Otherwise evaluate as expression
      val = eval_expr(stream)
      # Handle infix inside parens
      while stream.peek && stream.peek.type == :infix_op
        op = stream.consume.value
        right = eval_expr(stream)
        val = apply_infix(op, val, right)
      end
      stream.consume if stream.peek&.type == :right_paren  # consume )
      val
    end

    # Call a named procedure, reading args from stream
    def call_proc(name, stream, override_min = nil, override_max = nil)
      proc_obj = @workspace.lookup(name)
      raise LogoError, "I don't know how to #{name}" unless proc_obj

      n_inputs = proc_obj.default_inputs
      min_inputs = override_min || proc_obj.min_inputs
      max_inputs = override_max || proc_obj.max_inputs

      args = []
      n_inputs.times do
        stream.skip_newlines
        break if stream.empty?
        break if stream.peek&.type == :right_paren
        break if stream.peek&.type == :newline  # shouldn't happen after skip, but safety
        args << eval_expr(stream)
      end

      call_procedure(proc_obj, args)
    end

    # Call a procedure object with given args
    def call_procedure(proc_obj, args)
      if proc_obj.primitive?
        proc_obj.body.call(self, *args)
      elsif proc_obj.macro?
        result = run_user_proc(proc_obj, args)
        # Macro returns a list to evaluate
        if result.is_a?(Array)
          run_list(result)
        else
          result
        end
      else
        run_user_proc(proc_obj, args)
      end
    end

    # Run a user-defined procedure with given args
    def run_user_proc(proc_obj, args)
      @env.push_frame
      begin
        # Bind inputs
        required_inputs = proc_obj.inputs.select { |i| i[:type] == :required }
        optional_inputs = proc_obj.inputs.select { |i| i[:type] == :optional }
        rest_input = proc_obj.inputs.find { |i| i[:type] == :rest }

        arg_idx = 0
        required_inputs.each do |inp|
          val = args[arg_idx]
          raise LogoError, "#{proc_obj.name} needs #{required_inputs.size} inputs" if val.nil?
          @env.localmake(inp[:name], val)
          arg_idx += 1
        end

        optional_inputs.each do |inp|
          val = args[arg_idx]
          if val.nil?
            # Use default
            default_val = inp[:default]
            if default_val.is_a?(Array)
              default_val = run_list_value(default_val)
            end
            @env.localmake(inp[:name], default_val)
          else
            @env.localmake(inp[:name], val)
            arg_idx += 1
          end
        end

        if rest_input
          @env.localmake(rest_input[:name], args[arg_idx..] || [])
        end

        # Run body with GOTO support
        run_proc_body(proc_obj)
      rescue StopSignal
        nil
      rescue OutputSignal => e
        e.value
      ensure
        @env.pop_frame
      end
    end

    def run_proc_body(proc_obj)
      body = proc_obj.body || []
      # Scan for TAGs
      tags = {}
      body.each_with_index do |line, i|
        if line.is_a?(Array) && line.size >= 2 &&
           line[0].to_s.upcase == 'TAG'
          tag_val = line[1]
          tag_name = logo_to_word(tag_val).upcase
          tags[tag_name] = i
        end
      end

      i = 0
      result = nil
      while i < body.size
        line = body[i]
        begin
          if line.is_a?(Array)
            result = run_list(line)
          end
          i += 1
        rescue GotoSignal => e
          tag = e.tag.upcase
          raise LogoError, "TAG #{tag} not found in #{proc_obj.name}" unless tags.key?(tag)
          i = tags[tag]
        end
      end
      result
    end

    # Run a Logo list as instructions, returning last value
    def run_list(list)
      return nil if list.nil? || list.empty?
      src = list_to_source(list)
      tokens = Tokenizer.new(src).tokenize
      stream = TokenStream.new(tokens)
      result = nil
      until stream.empty?
        val = eval_expr(stream)
        result = val unless val.nil?
      end
      @last_value = result
      result
    end

    # Run list and return value (may raise OutputSignal)
    def run_list_value(list)
      return nil if list.nil? || list.empty?
      src = list_to_source(list)
      tokens = Tokenizer.new(src).tokenize
      stream = TokenStream.new(tokens)
      result = nil
      begin
        until stream.empty?
          val = eval_expr(stream)
          result = val unless val.nil?
        end
      rescue OutputSignal => e
        return e.value
      end
      result
    end

    # Convert a logo list back to source string
    def list_to_source(list)
      list.map { |item| logo_item_to_source(item) }.join(' ')
    end

    def logo_item_to_source(item)
      case item
      when Array
        "[#{list_to_source(item)}]"
      when LogoArray
        item.to_s
      when String
        # Check if it looks like a variable reference
        if item.start_with?(':')
          item
        elsif item =~ /\A[+\-*\/=<>]+\z/ || item == '(' || item == ')'
          item
        else
          item
        end
      when Numeric
        logo_to_s(item)
      else
        item.to_s
      end
    end

    # Convert a Logo value to its string representation
    def logo_to_s(val)
      case val
      when Integer then val.to_s
      when Float
        if val == val.to_i && val.finite?
          val.to_i.to_s
        else
          # Try to represent cleanly
          s = val.to_s
          s
        end
      when String then val
      when Array then "[#{val.map { |v| logo_show_str(v) }.join(' ')}]"
      when LogoArray then val.to_s
      when NilClass then ''
      else val.to_s
      end
    end

    # String representation for PRINT (top-level list without brackets)
    def logo_print_str(val)
      case val
      when Array
        val.map { |v| logo_show_str(v) }.join(' ')
      when LogoArray
        val.to_s
      else
        logo_to_s(val)
      end
    end

    # String representation for SHOW (with brackets)
    def logo_show_str(val)
      case val
      when Array
        "[#{val.map { |v| logo_show_str(v) }.join(' ')}]"
      when LogoArray
        val.to_s
      when String
        val
      when Numeric
        logo_to_s(val)
      when NilClass
        ''
      else
        val.to_s
      end
    end

    # Convert to word (string)
    def logo_to_word(val)
      case val
      when String
        # Strip leading quote character (used in list storage for round-trip serialization)
        val.start_with?('"') ? val[1..] : val
      when Numeric then logo_to_s(val)
      when Array then val.map { |v| logo_to_word(v) }.join(' ')
      else val.to_s
      end
    end

    # Test if a value is Logo true
    def logo_true?(val)
      val.to_s.downcase == 'true'
    end

    # Convert to Ruby Numeric
    def to_number(val)
      case val
      when Integer then val
      when Float then val
      when String
        if val =~ /\A-?[0-9]+\z/
          val.to_i
        elsif val =~ /\A-?[0-9]*\.[0-9]+([eE][+\-]?[0-9]+)?\z/
          val.to_f
        elsif val =~ /\A-?[0-9]+[eE][+\-]?[0-9]+\z/
          val.to_f
        else
          raise LogoError, "#{val} is not a number"
        end
      when Numeric then val
      else
        raise LogoError, "#{val.inspect} is not a number"
      end
    end

    # Test Logo equality
    def logo_equal?(a, b)
      case [a.class, b.class]
      when [Integer, Integer] then a == b
      when [Float, Float] then a == b
      when [Integer, Float] then a.to_f == b
      when [Float, Integer] then a == b.to_f
      when [String, String]
        caseignored = begin
          @env.defined?('CASEIGNOREDP') && logo_true?(@env.thing('CASEIGNOREDP'))
        rescue
          true
        end
        caseignored ? a.downcase == b.downcase : a == b
      when [Array, Array]
        return false if a.size != b.size
        a.zip(b).all? { |x, y| logo_equal?(x, y) }
      else
        if (a.is_a?(Integer) || a.is_a?(Float)) && (b.is_a?(String))
          begin; logo_equal?(a, to_number(b)); rescue; false; end
        elsif (a.is_a?(String)) && (b.is_a?(Integer) || b.is_a?(Float))
          begin; logo_equal?(to_number(a), b); rescue; false; end
        else
          a == b
        end
      end
    end

    # Apply an infix operator
    def apply_infix(op, left, right)
      case op
      when '+'
        if left.is_a?(Numeric) || right.is_a?(Numeric)
          to_number(left) + to_number(right)
        else
          # Both strings - concatenate? UCB Logo does arithmetic
          to_number(left) + to_number(right)
        end
      when '-'
        to_number(left) - to_number(right)
      when '*'
        to_number(left) * to_number(right)
      when '/'
        r = to_number(right)
        raise LogoError, "Division by zero" if r == 0
        l = to_number(left)
        result = l.to_f / r.to_f
        result == result.to_i ? result.to_i : result
      when '='
        logo_equal?(left, right) ? 'true' : 'false'
      when '<>'
        logo_equal?(left, right) ? 'false' : 'true'
      when '<'
        (to_number(left) < to_number(right)) ? 'true' : 'false'
      when '>'
        (to_number(left) > to_number(right)) ? 'true' : 'false'
      when '<='
        (to_number(left) <= to_number(right)) ? 'true' : 'false'
      when '>='
        (to_number(left) >= to_number(right)) ? 'true' : 'false'
      else
        raise LogoError, "Unknown operator: #{op}"
      end
    end

    # Output methods
    def logo_print_output(str)
      out = write_stream || $stdout
      out.puts(str)
      dribble_file&.puts(str)
    end

    def logo_type_output(str)
      out = write_stream || $stdout
      out.print(str)
      dribble_file&.print(str)
    end

    # Read methods
    def read_line
      inp = read_stream || $stdin
      inp.gets
    end

    def read_char
      inp = read_stream || $stdin
      c = inp.getc
      c
    end

    # Full path with prefix
    def full_path(filename)
      return filename if filename.start_with?('/') || @file_prefix.nil? || @file_prefix.empty?
      File.join(@file_prefix, filename)
    end

    # Load a file
    def load_file(filename)
      source = File.read(filename)
      run(source)
    rescue Errno::ENOENT
      raise LogoError, "File not found: #{filename}"
    end

    # Parse the TO line, read body until END, define procedure
    def parse_to(stream, type = :user)
      # Read procedure name
      raise LogoError, "TO: expected procedure name" if stream.empty?
      name_tok = stream.consume
      name = logo_to_word(name_tok.value || name_tok.to_s).upcase

      # Read input specs
      inputs = []
      while stream.peek && stream.peek.type != :newline && !stream.empty?
        tok = stream.peek
        if tok.type == :variable
          stream.consume
          inputs << { name: tok.value.upcase, type: :required }
        elsif tok.type == :number
          # Default input count - skip for now
          stream.consume
        elsif tok.type == :left_bracket
          # Optional or rest input
          stream.consume  # consume [
          inner = []
          until stream.empty? || stream.peek.type == :right_bracket
            inner << stream.consume
          end
          stream.consume if stream.peek&.type == :right_bracket
          if inner.size == 1 && inner[0].type == :variable
            inputs << { name: inner[0].value.upcase, type: :rest }
          elsif inner.size >= 2 && inner[0].type == :variable
            # Optional with default - evaluate default later
            default_tokens = inner[1..]
            default_val = default_tokens[0]&.value
            inputs << { name: inner[0].value.upcase, default: default_val, type: :optional }
          end
        else
          break
        end
      end

      # Read body until END
      body = read_procedure_body(stream)

      required = inputs.count { |i| i[:type] == :required }
      optional = inputs.count { |i| i[:type] == :optional }
      has_rest = inputs.any? { |i| i[:type] == :rest }

      proc_obj = Procedure.new(
        name: name,
        inputs: inputs,
        body: body,
        min_inputs: required,
        default_inputs: required + optional,
        max_inputs: has_rest ? nil : required + optional,
        type: type
      )
      @workspace.define(name, proc_obj)
      nil
    end

    def read_procedure_body(stream)
      body = []
      current_line = []

      until stream.empty?
        tok = stream.peek
        if tok.type == :newline
          stream.consume
          body << current_line unless current_line.empty?
          current_line = []
        elsif tok.type == :name && tok.value.upcase == 'END'
          stream.consume
          body << current_line unless current_line.empty?
          break
        else
          stream.consume
          current_line << token_to_logo_value(tok)
        end
      end
      body
    end

    # Edit in external editor
    def edit_in_editor(editor, contentslist)
      require 'tempfile'
      tf = Tempfile.new(['loco', '.lgo'])
      begin
        # Write current definitions
        @workspace.user_procedures.each do |pname|
          proc_obj = @workspace.lookup(pname)
          next unless proc_obj
          tf.puts format_proc_for_edit(proc_obj)
          tf.puts
        end
        tf.close
        system(editor, tf.path)
        # Re-load
        run(File.read(tf.path))
      ensure
        tf.unlink
      end
    end

    def format_proc_for_edit(proc_obj)
      lines = []
      parts = ["TO #{proc_obj.name}"]
      proc_obj.inputs.each do |inp|
        case inp[:type]
        when :required then parts << ":#{inp[:name]}"
        when :optional then parts << "[:#{inp[:name]} #{logo_show_str(inp[:default])}]"
        when :rest then parts << "[:#{inp[:name]}]"
        end
      end
      lines << parts.join(' ')
      (proc_obj.body || []).each do |line|
        lines << line.map { |tok| logo_show_str(tok) }.join(' ')
      end
      lines << "END"
      lines.join("\n")
    end

    # REPL
    def repl
      puts "Welcome to Loco - A Logo Interpreter"
      puts "Type BYE to exit"
      puts

      loop do
        print '? '
        $stdout.flush
        line = $stdin.gets
        break unless line

        line = line.chomp
        next if line.empty?

        begin
          # Handle multi-line TO definitions
          if line =~ /\ATO\s/i || line =~ /\A\.MACRO\s/i
            full = line + "\n"
            loop do
              print '> '
              $stdout.flush
              more = $stdin.gets
              break unless more
              full += more
              break if more.strip.upcase == 'END'
            end
            run(full)
          else
            result = run(line)
            if result && !result.nil?
              puts "You don't say what to do with #{logo_show_str(result)}"
            end
          end
        rescue StopSignal
          # silently ignore STOP at top level
        rescue OutputSignal => e
          puts "You don't say what to do with #{logo_show_str(e.value)}"
        rescue PauseSignal
          puts "Paused"
        rescue ThrowSignal => e
          puts "Throw from non-catch: Tag: #{e.tag}  Value: #{logo_show_str(e.value)}"
        rescue LogoError => e
          puts e.message
          @last_error = e
        rescue Interrupt
          puts "\nInterrupted"
        rescue => e
          puts "Error: #{e.message}"
        end
      end
    end

    # Handle TO as a special form in the stream
    def handle_to_special_form(stream, type = :user)
      parse_to(stream, type)
    end

    private

    # Override eval_primary to handle TO as special form
    def eval_primary(stream)
      return nil if stream.empty?
      tok = stream.peek

      case tok.type
      when :number
        stream.consume
        tok.value
      when :word
        stream.consume
        tok.value
      when :variable
        stream.consume
        @env.thing(tok.value)
      when :left_bracket
        collect_list(stream)
      when :left_brace
        collect_array(stream)
      when :left_paren
        eval_paren(stream)
      when :infix_op
        if tok.value == '-'
          stream.consume
          val = eval_primary(stream)
          -to_number(val)
        else
          raise LogoError, "Unexpected operator: #{tok.value}"
        end
      when :name
        name = tok.value.upcase
        if name == 'TO'
          stream.consume
          handle_to_special_form(stream, :user)
          nil
        elsif name == '.MACRO'
          stream.consume
          handle_to_special_form(stream, :macro)
          nil
        elsif name == 'MINUS'
          stream.consume
          val = eval_primary(stream)
          -to_number(val)
        else
          stream.consume
          call_proc(name, stream)
        end
      when :right_bracket, :right_paren, :right_brace
        nil
      else
        stream.consume
        tok.value
      end
    end
  end
end
