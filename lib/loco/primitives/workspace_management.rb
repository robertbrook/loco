module Loco
  module Primitives
    module WorkspaceManagement
      def register_workspace_management
        # MAKE
        register_primitive('MAKE', 2, 2, 2) do |interp, varname, value|
          name = interp.logo_to_word(varname)
          interp.env.make(name, value)
          nil
        end

        # NAME (reversed MAKE - library)
        register_primitive('NAME', 2, 2, 2) do |interp, value, varname|
          name = interp.logo_to_word(varname)
          interp.env.make(name, value)
          nil
        end

        # LOCAL
        register_primitive('LOCAL', 1, 1, -1) do |interp, *args|
          args.each do |arg|
            if arg.is_a?(Array)
              arg.each { |a| interp.env.local(interp.logo_to_word(a)) }
            else
              interp.env.local(interp.logo_to_word(arg))
            end
          end
          nil
        end

        # LOCALMAKE (library)
        register_primitive('LOCALMAKE', 2, 2, 2) do |interp, varname, value|
          name = interp.logo_to_word(varname)
          interp.env.localmake(name, value)
          nil
        end

        # THING
        register_primitive('THING', 1, 1, 1) do |interp, varname|
          name = interp.logo_to_word(varname)
          interp.env.thing(name)
        end

        # GLOBAL
        register_primitive('GLOBAL', 1, 1, -1) do |interp, *args|
          args.each do |arg|
            if arg.is_a?(Array)
              arg.each { |a| interp.env.global(interp.logo_to_word(a)) }
            else
              interp.env.global(interp.logo_to_word(arg))
            end
          end
          nil
        end

        # PPROP
        register_primitive('PPROP', 3, 3, 3) do |interp, plistname, propname, value|
          pl = interp.logo_to_word(plistname)
          pr = interp.logo_to_word(propname)
          interp.workspace.pprop(pl, pr, value)
          nil
        end

        # GPROP
        register_primitive('GPROP', 2, 2, 2) do |interp, plistname, propname|
          pl = interp.logo_to_word(plistname)
          pr = interp.logo_to_word(propname)
          result = interp.workspace.gprop(pl, pr)
          result.nil? ? [] : result
        end

        # REMPROP
        register_primitive('REMPROP', 2, 2, 2) do |interp, plistname, propname|
          pl = interp.logo_to_word(plistname)
          pr = interp.logo_to_word(propname)
          interp.workspace.remprop(pl, pr)
          nil
        end

        # PLIST
        register_primitive('PLIST', 1, 1, 1) do |interp, plistname|
          pl = interp.logo_to_word(plistname)
          interp.workspace.plist(pl)
        end

        # PROCEDUREP / PROCEDURE?
        register_primitive('PROCEDUREP', 1, 1, 1) do |interp, name|
          n = interp.logo_to_word(name).upcase
          interp.workspace.procedure?(n) ? 'true' : 'false'
        end
        register_alias('PROCEDURE?', 'PROCEDUREP')

        # PRIMITIVEP / PRIMITIVE?
        register_primitive('PRIMITIVEP', 1, 1, 1) do |interp, name|
          n = interp.logo_to_word(name).upcase
          interp.workspace.primitive?(n) ? 'true' : 'false'
        end
        register_alias('PRIMITIVE?', 'PRIMITIVEP')

        # DEFINEDP / DEFINED?
        register_primitive('DEFINEDP', 1, 1, 1) do |interp, name|
          n = interp.logo_to_word(name).upcase
          interp.workspace.defined?(n) ? 'true' : 'false'
        end
        register_alias('DEFINED?', 'DEFINEDP')

        # NAMEP / NAME?
        register_primitive('NAMEP', 1, 1, 1) do |interp, name|
          n = interp.logo_to_word(name)
          interp.env.defined?(n) ? 'true' : 'false'
        end
        register_alias('NAME?', 'NAMEP')

        # PLISTP / PLIST?
        register_primitive('PLISTP', 1, 1, 1) do |interp, name|
          n = interp.logo_to_word(name).upcase
          !interp.workspace.plist(n).empty? ? 'true' : 'false'
        end
        register_alias('PLIST?', 'PLISTP')

        # CONTENTS
        register_primitive('CONTENTS', 0, 0, 0) do |interp|
          procs = interp.workspace.user_procedures.reject { |n| interp.workspace.buried?(n) }
          vars = interp.env.global_names.reject { |n| interp.workspace.buried?(n) }
          plists = interp.workspace.plist_names.reject { |n| interp.workspace.buried?(n) }
          [procs, vars, plists]
        end

        # BURIED
        register_primitive('BURIED', 0, 0, 0) do |interp|
          all_names = interp.workspace.all_procedures +
                      interp.env.global_names +
                      interp.workspace.plist_names
          buried = all_names.select { |n| interp.workspace.buried?(n) }
          [buried, [], []]
        end

        # TRACED
        register_primitive('TRACED', 0, 0, 0) do |interp|
          traced = interp.workspace.all_procedures.select { |n| interp.workspace.traced?(n) }
          [traced, [], []]
        end

        # STEPPED
        register_primitive('STEPPED', 0, 0, 0) do |interp|
          stepped = interp.workspace.all_procedures.select { |n| interp.workspace.stepped?(n) }
          [stepped, [], []]
        end

        # PROCEDURES
        register_primitive('PROCEDURES', 0, 0, 0) do |interp|
          interp.workspace.user_procedures.reject { |n| interp.workspace.buried?(n) }
        end

        # PRIMITIVES
        register_primitive('PRIMITIVES', 0, 0, 0) do |interp|
          interp.workspace.primitive_procedures
        end

        # NAMES
        register_primitive('NAMES', 0, 0, 0) do |interp|
          vars = interp.env.global_names.reject { |n| interp.workspace.buried?(n) }
          [[], vars, []]
        end

        # PLISTS
        register_primitive('PLISTS', 0, 0, 0) do |interp|
          pls = interp.workspace.plist_names.reject { |n| interp.workspace.buried?(n) }
          [[], [], pls]
        end

        # ARITY
        register_primitive('ARITY', 1, 1, 1) do |interp, name|
          n = interp.logo_to_word(name).upcase
          proc_obj = interp.workspace.lookup(n)
          raise LogoError, "ARITY: #{name} is not a procedure" unless proc_obj
          [proc_obj.min_inputs, proc_obj.default_inputs, proc_obj.max_inputs || -1]
        end

        # NODES
        register_primitive('NODES', 0, 0, 0) do |interp|
          GC.start
          [0, 0]
        end

        # PRINTOUT / PO
        register_primitive('PRINTOUT', 1, 1, 1) do |interp, contentslist|
          cl = normalize_contents_list(interp, contentslist)
          # Print procedures
          (cl[0] || []).each do |pname|
            proc_obj = interp.workspace.lookup(pname.to_s.upcase)
            next unless proc_obj && proc_obj.user?
            interp.logo_print_output(format_procedure(interp, proc_obj))
          end
          # Print variables
          (cl[1] || []).each do |vname|
            begin
              val = interp.env.thing(vname.to_s)
              interp.logo_print_output("MAKE \"#{vname} #{interp.logo_show_str(val)}")
            rescue LogoError
              # variable not defined
            end
          end
          # Print property lists
          (cl[2] || []).each do |plname|
            plist = interp.workspace.plist(plname.to_s)
            unless plist.empty?
              interp.logo_print_output("PLIST #{interp.logo_show_str(plname)} #{interp.logo_show_str(plist)}")
            end
          end
          nil
        end
        register_alias('PO', 'PRINTOUT')

        # POALL
        register_primitive('POALL', 0, 0, 0) do |interp|
          procs = interp.workspace.user_procedures
          procs.each do |pname|
            proc_obj = interp.workspace.lookup(pname)
            next unless proc_obj && proc_obj.user?
            interp.logo_print_output(format_procedure(interp, proc_obj))
          end
          nil
        end

        # POPS
        register_primitive('POPS', 0, 0, 0) do |interp|
          interp.workspace.user_procedures.each do |pname|
            proc_obj = interp.workspace.lookup(pname)
            next unless proc_obj
            interp.logo_print_output(format_procedure_title(interp, proc_obj))
          end
          nil
        end

        # PONS
        register_primitive('PONS', 0, 0, 0) do |interp|
          interp.env.global_names.each do |vname|
            begin
              val = interp.env.thing(vname)
              interp.logo_print_output("MAKE \"#{vname} #{interp.logo_show_str(val)}")
            rescue LogoError
              # skip
            end
          end
          nil
        end

        # POPLS
        register_primitive('POPLS', 0, 0, 0) do |interp|
          interp.workspace.plist_names.each do |plname|
            plist = interp.workspace.plist(plname)
            interp.logo_print_output("PLIST #{interp.logo_show_str(plname)} #{interp.logo_show_str(plist)}")
          end
          nil
        end

        # PON
        register_primitive('PON', 1, 1, 1) do |interp, varname|
          names = varname.is_a?(Array) ? varname : [varname]
          names.each do |n|
            begin
              val = interp.env.thing(interp.logo_to_word(n))
              interp.logo_print_output("MAKE \"#{interp.logo_to_word(n)} #{interp.logo_show_str(val)}")
            rescue LogoError
              # skip
            end
          end
          nil
        end

        # POPL
        register_primitive('POPL', 1, 1, 1) do |interp, plname|
          names = plname.is_a?(Array) ? plname : [plname]
          names.each do |n|
            pl = interp.logo_to_word(n)
            plist = interp.workspace.plist(pl)
            interp.logo_print_output("PLIST #{interp.logo_show_str(pl)} #{interp.logo_show_str(plist)}")
          end
          nil
        end

        # POT
        register_primitive('POT', 1, 1, 1) do |interp, contentslist|
          cl = normalize_contents_list(interp, contentslist)
          (cl[0] || []).each do |pname|
            proc_obj = interp.workspace.lookup(pname.to_s.upcase)
            next unless proc_obj && proc_obj.user?
            interp.logo_print_output(format_procedure_title(interp, proc_obj))
          end
          nil
        end

        # POTS
        register_primitive('POTS', 0, 0, 0) do |interp|
          interp.workspace.user_procedures.each do |pname|
            proc_obj = interp.workspace.lookup(pname)
            next unless proc_obj
            interp.logo_print_output(format_procedure_title(interp, proc_obj))
          end
          nil
        end

        # TEXT
        register_primitive('TEXT', 1, 1, 1) do |interp, name|
          n = interp.logo_to_word(name).upcase
          proc_obj = interp.workspace.lookup(n)
          raise LogoError, "TEXT: #{name} is not defined" unless proc_obj && proc_obj.user?
          procedure_to_text(proc_obj)
        end

        # FULLTEXT
        register_primitive('FULLTEXT', 1, 1, 1) do |interp, name|
          n = interp.logo_to_word(name).upcase
          proc_obj = interp.workspace.lookup(n)
          raise LogoError, "FULLTEXT: #{name} is not defined" unless proc_obj && proc_obj.user?
          procedure_to_text(proc_obj)
        end

        # DEFINE
        register_primitive('DEFINE', 2, 2, 2) do |interp, procname, text|
          name = interp.logo_to_word(procname).upcase
          raise LogoError, "DEFINE: second input must be a list" unless text.is_a?(Array)
          proc_obj = build_procedure_from_text_wm(interp, name, text, :user)
          interp.workspace.define(name, proc_obj)
          nil
        end

        # COPYDEF
        register_primitive('COPYDEF', 2, 2, 2) do |interp, newname, oldname|
          nn = interp.logo_to_word(newname).upcase
          on = interp.logo_to_word(oldname).upcase
          old_proc = interp.workspace.lookup(on)
          raise LogoError, "COPYDEF: #{oldname} is not defined" unless old_proc
          interp.workspace.define(nn, old_proc)
          nil
        end

        # ERASE / ER
        register_primitive('ERASE', 1, 1, 1) do |interp, contentslist|
          cl = normalize_contents_list(interp, contentslist)
          (cl[0] || []).each { |n| interp.workspace.erase(n.to_s) }
          (cl[1] || []).each { |n| interp.env.global_set(n.to_s, nil) }
          (cl[2] || []).each { |n| interp.workspace.erase_plist(n.to_s) }
          nil
        end
        register_alias('ER', 'ERASE')

        # ERALL
        register_primitive('ERALL', 0, 0, 0) do |interp|
          interp.workspace.user_procedures.each { |n| interp.workspace.erase(n) unless interp.workspace.buried?(n) }
          nil
        end

        # ERPS
        register_primitive('ERPS', 0, 0, 0) do |interp|
          interp.workspace.user_procedures.each { |n| interp.workspace.erase(n) }
          nil
        end

        # ERNS
        register_primitive('ERNS', 0, 0, 0) do |interp|
          interp.env.global_names.each { |n| interp.env.global_set(n, nil) }
          nil
        end

        # ERPLS
        register_primitive('ERPLS', 0, 0, 0) do |interp|
          interp.workspace.plist_names.each { |n| interp.workspace.erase_plist(n) }
          nil
        end

        # ERN
        register_primitive('ERN', 1, 1, 1) do |interp, varname|
          names = varname.is_a?(Array) ? varname : [varname]
          names.each { |n| interp.env.global_set(interp.logo_to_word(n), nil) }
          nil
        end

        # ERPL
        register_primitive('ERPL', 1, 1, 1) do |interp, plname|
          names = plname.is_a?(Array) ? plname : [plname]
          names.each { |n| interp.workspace.erase_plist(interp.logo_to_word(n)) }
          nil
        end

        # BURY
        register_primitive('BURY', 1, 1, 1) do |interp, contentslist|
          cl = normalize_contents_list(interp, contentslist)
          (cl[0] || []).each { |n| interp.workspace.bury(n.to_s) }
          (cl[1] || []).each { |n| interp.workspace.bury(n.to_s) }
          (cl[2] || []).each { |n| interp.workspace.bury(n.to_s) }
          nil
        end

        # UNBURY
        register_primitive('UNBURY', 1, 1, 1) do |interp, contentslist|
          cl = normalize_contents_list(interp, contentslist)
          (cl[0] || []).each { |n| interp.workspace.unbury(n.to_s) }
          (cl[1] || []).each { |n| interp.workspace.unbury(n.to_s) }
          (cl[2] || []).each { |n| interp.workspace.unbury(n.to_s) }
          nil
        end

        # BURYALL
        register_primitive('BURYALL', 0, 0, 0) do |interp|
          interp.workspace.all_procedures.each { |n| interp.workspace.bury(n) }
          nil
        end

        # UNBURYALL
        register_primitive('UNBURYALL', 0, 0, 0) do |interp|
          interp.workspace.all_procedures.each { |n| interp.workspace.unbury(n) }
          nil
        end

        # BURYNAME
        register_primitive('BURYNAME', 1, 1, 1) do |interp, varname|
          names = varname.is_a?(Array) ? varname : [varname]
          names.each { |n| interp.workspace.bury(interp.logo_to_word(n)) }
          nil
        end

        # UNBURYNAME
        register_primitive('UNBURYNAME', 1, 1, 1) do |interp, varname|
          names = varname.is_a?(Array) ? varname : [varname]
          names.each { |n| interp.workspace.unbury(interp.logo_to_word(n)) }
          nil
        end

        # BURIEDP / BURIED?
        register_primitive('BURIEDP', 1, 1, 1) do |interp, name|
          n = interp.logo_to_word(name).upcase
          interp.workspace.buried?(n) ? 'true' : 'false'
        end
        register_alias('BURIED?', 'BURIEDP')

        # TRACE
        register_primitive('TRACE', 1, 1, 1) do |interp, contentslist|
          cl = normalize_contents_list(interp, contentslist)
          (cl[0] || []).each { |n| interp.workspace.trace(n.to_s) }
          nil
        end

        # UNTRACE
        register_primitive('UNTRACE', 1, 1, 1) do |interp, contentslist|
          cl = normalize_contents_list(interp, contentslist)
          (cl[0] || []).each { |n| interp.workspace.untrace(n.to_s) }
          nil
        end

        # TRACEDP / TRACED?
        register_primitive('TRACEDP', 1, 1, 1) do |interp, name|
          n = interp.logo_to_word(name).upcase
          interp.workspace.traced?(n) ? 'true' : 'false'
        end
        register_alias('TRACED?', 'TRACEDP')

        # STEP
        register_primitive('STEP', 1, 1, 1) do |interp, contentslist|
          cl = normalize_contents_list(interp, contentslist)
          (cl[0] || []).each { |n| interp.workspace.step(n.to_s) }
          nil
        end

        # UNSTEP
        register_primitive('UNSTEP', 1, 1, 1) do |interp, contentslist|
          cl = normalize_contents_list(interp, contentslist)
          (cl[0] || []).each { |n| interp.workspace.unstep(n.to_s) }
          nil
        end

        # STEPPEDP / STEPPED?
        register_primitive('STEPPEDP', 1, 1, 1) do |interp, name|
          n = interp.logo_to_word(name).upcase
          interp.workspace.stepped?(n) ? 'true' : 'false'
        end
        register_alias('STEPPED?', 'STEPPEDP')

        # EDIT / ED
        register_primitive('EDIT', 0, 0, 1) do |interp, contentslist = nil|
          editor = ENV['EDITOR'] || 'vi'
          interp.edit_in_editor(editor, contentslist)
          nil
        end
        register_alias('ED', 'EDIT')

        # EDITFILE
        register_primitive('EDITFILE', 1, 1, 1) do |interp, filename|
          editor = ENV['EDITOR'] || 'vi'
          name = interp.full_path(interp.logo_to_word(filename))
          system("#{editor} #{name}")
          nil
        end

        # SAVE
        register_primitive('SAVE', 1, 1, 1) do |interp, filename|
          name = interp.full_path(interp.logo_to_word(filename))
          File.open(name, 'w') do |f|
            interp.workspace.user_procedures.each do |pname|
              proc_obj = interp.workspace.lookup(pname)
              next unless proc_obj && proc_obj.user?
              f.puts format_procedure(interp, proc_obj)
              f.puts
            end
            interp.env.global_names.each do |vname|
              begin
                val = interp.env.thing(vname)
                f.puts "MAKE \"#{vname} #{interp.logo_show_str(val)}"
              rescue LogoError
                # skip
              end
            end
          end
          nil
        end

        # SAVEL
        register_primitive('SAVEL', 2, 2, 2) do |interp, contentslist, filename|
          name = interp.full_path(interp.logo_to_word(filename))
          cl = normalize_contents_list(interp, contentslist)
          File.open(name, 'w') do |f|
            (cl[0] || []).each do |pname|
              proc_obj = interp.workspace.lookup(pname.to_s.upcase)
              next unless proc_obj && proc_obj.user?
              f.puts format_procedure(interp, proc_obj)
              f.puts
            end
            (cl[1] || []).each do |vname|
              begin
                val = interp.env.thing(vname.to_s)
                f.puts "MAKE \"#{vname} #{interp.logo_show_str(val)}"
              rescue LogoError
                # skip
              end
            end
          end
          nil
        end

        # LOAD
        register_primitive('LOAD', 1, 1, 1) do |interp, filename|
          name = interp.full_path(interp.logo_to_word(filename))
          interp.load_file(name)
          nil
        end

        # CSLSLOAD
        register_primitive('CSLSLOAD', 1, 1, 1) do |interp, name|
          libname = interp.logo_to_word(name)
          libpath = File.join(interp.lib_loc || '.', libname + '.lgo')
          interp.load_file(libpath) if File.exist?(libpath)
          nil
        end

        # HELP
        register_primitive('HELP', 0, 0, 1) do |interp, name = nil|
          if name
            n = interp.logo_to_word(name).upcase
            proc_obj = interp.workspace.lookup(n)
            if proc_obj
              interp.logo_print_output("#{n}: min=#{proc_obj.min_inputs} default=#{proc_obj.default_inputs} max=#{proc_obj.max_inputs || 'unlimited'}")
            else
              interp.logo_print_output("No help for #{name}")
            end
          else
            interp.logo_print_output("Type HELP \"procname for help on a procedure")
          end
          nil
        end

        # SETEDITOR
        register_primitive('SETEDITOR', 1, 1, 1) do |interp, path|
          ENV['EDITOR'] = interp.logo_to_word(path)
          nil
        end

        # SETLIBLOC
        register_primitive('SETLIBLOC', 1, 1, 1) do |interp, path|
          interp.lib_loc = interp.logo_to_word(path)
          nil
        end

        # SETHELPLOC
        register_primitive('SETHELPLOC', 1, 1, 1) do |interp, path|
          interp.help_loc = interp.logo_to_word(path)
          nil
        end

        # GC
        register_primitive('GC', 0, 0, 1) do |interp, arg = nil|
          GC.start
          nil
        end

        # .SETSEGMENTSIZE
        register_primitive('.SETSEGMENTSIZE', 1, 1, 1) do |interp, num|
          nil
        end

        # NAMELIST
        register_primitive('NAMELIST', 1, 1, 1) do |interp, varname|
          names = varname.is_a?(Array) ? varname.map { |n| interp.logo_to_word(n) } : [interp.logo_to_word(varname)]
          [[], names, []]
        end

        # PLLIST
        register_primitive('PLLIST', 1, 1, 1) do |interp, plname|
          names = plname.is_a?(Array) ? plname.map { |n| interp.logo_to_word(n) } : [interp.logo_to_word(plname)]
          [[], [], names]
        end

        # EDALL, EDPS, EDNS, EDPLS
        ['EDALL', 'EDPS', 'EDNS', 'EDPLS'].each do |cmd|
          register_primitive(cmd, 0, 0, 0) do |interp|
            editor = ENV['EDITOR'] || 'vi'
            interp.edit_in_editor(editor, nil)
            nil
          end
        end

        register_primitive('EDN', 1, 1, 1) do |interp, varname|
          nil
        end

        register_primitive('EDPL', 1, 1, 1) do |interp, plname|
          nil
        end
      end

      private

      def normalize_contents_list(interp, cl)
        if cl.is_a?(Array) && cl.size == 3 && cl.all? { |e| e.is_a?(Array) }
          cl
        elsif cl.is_a?(Array)
          [cl, [], []]
        elsif cl.is_a?(String)
          [[cl], [], []]
        else
          [[], [], []]
        end
      end

      def procedure_to_text(proc_obj)
        input_header = proc_obj.inputs.map do |inp|
          case inp[:type]
          when :required then inp[:name]
          when :optional then [inp[:name], inp[:default]]
          when :rest then [inp[:name]]
          end
        end
        [input_header] + (proc_obj.body || [])
      end

      def format_procedure(interp, proc_obj)
        lines = []
        title = format_procedure_title(interp, proc_obj)
        lines << title
        (proc_obj.body || []).each do |line|
          lines << line.map { |tok| interp.logo_show_str(tok) }.join(' ')
        end
        lines << "END"
        lines.join("\n")
      end

      def format_procedure_title(interp, proc_obj)
        prefix = proc_obj.type == :macro ? '.MACRO' : 'TO'
        parts = ["#{prefix} #{proc_obj.name}"]
        proc_obj.inputs.each do |inp|
          case inp[:type]
          when :required
            parts << ":#{inp[:name]}"
          when :optional
            parts << "[:#{inp[:name]} #{interp.logo_show_str(inp[:default])}]"
          when :rest
            parts << "[:#{inp[:name]}]"
          end
        end
        parts.join(' ')
      end

      def build_procedure_from_text_wm(interp, name, text, type = :user)
        inputs = []
        body = []
        if text.size >= 1 && text[0].is_a?(Array)
          input_list = text[0]
          input_list.each do |inp|
            if inp.is_a?(String) || inp.is_a?(Numeric)
              inputs << { name: inp.to_s.upcase, type: :required }
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
