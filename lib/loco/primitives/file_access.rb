module Loco
  module Primitives
    module FileAccess
      def register_file_access
        # SETPREFIX
        register_primitive('SETPREFIX', 1, 1, 1) do |interp, str|
          interp.file_prefix = interp.logo_to_word(str)
          nil
        end

        # PREFIX
        register_primitive('PREFIX', 0, 0, 0) do |interp|
          interp.file_prefix || ''
        end

        # OPENREAD
        register_primitive('OPENREAD', 1, 1, 1) do |interp, filename|
          name = interp.full_path(interp.logo_to_word(filename))
          interp.open_files[name] = File.open(name, 'r')
          nil
        end

        # OPENWRITE
        register_primitive('OPENWRITE', 1, 1, 1) do |interp, filename|
          name = interp.full_path(interp.logo_to_word(filename))
          interp.open_files[name] = File.open(name, 'w')
          nil
        end

        # OPENAPPEND
        register_primitive('OPENAPPEND', 1, 1, 1) do |interp, filename|
          name = interp.full_path(interp.logo_to_word(filename))
          interp.open_files[name] = File.open(name, 'a')
          nil
        end

        # OPENUPDATE
        register_primitive('OPENUPDATE', 1, 1, 1) do |interp, filename|
          name = interp.full_path(interp.logo_to_word(filename))
          interp.open_files[name] = File.open(name, 'r+')
          nil
        end

        # CLOSE
        register_primitive('CLOSE', 1, 1, 1) do |interp, filename|
          name = interp.full_path(interp.logo_to_word(filename))
          f = interp.open_files.delete(name)
          f&.close
          nil
        end

        # ALLOPEN
        register_primitive('ALLOPEN', 0, 0, 0) do |interp|
          interp.open_files.keys
        end

        # CLOSEALL
        register_primitive('CLOSEALL', 0, 0, 0) do |interp|
          interp.open_files.each_value(&:close)
          interp.open_files.clear
          nil
        end

        # ERASEFILE / ERF
        register_primitive('ERASEFILE', 1, 1, 1) do |interp, filename|
          name = interp.full_path(interp.logo_to_word(filename))
          File.delete(name) if File.exist?(name)
          nil
        end
        register_alias('ERF', 'ERASEFILE')

        # DRIBBLE
        register_primitive('DRIBBLE', 1, 1, 1) do |interp, filename|
          name = interp.full_path(interp.logo_to_word(filename))
          interp.dribble_file = File.open(name, 'w')
          nil
        end

        # NODRIBBLE
        register_primitive('NODRIBBLE', 0, 0, 0) do |interp|
          interp.dribble_file&.close
          interp.dribble_file = nil
          nil
        end

        # SETREAD
        register_primitive('SETREAD', 1, 1, 1) do |interp, filename|
          name = interp.logo_to_word(filename)
          if name.empty?
            interp.read_stream = nil
          else
            full = interp.full_path(name)
            interp.read_stream = interp.open_files[full]
            raise LogoError, "SETREAD: #{name} is not open" unless interp.read_stream
          end
          nil
        end

        # SETWRITE
        register_primitive('SETWRITE', 1, 1, 1) do |interp, filename|
          name = interp.logo_to_word(filename)
          if name.empty?
            interp.write_stream = nil
          else
            full = interp.full_path(name)
            interp.write_stream = interp.open_files[full]
            raise LogoError, "SETWRITE: #{name} is not open" unless interp.write_stream
          end
          nil
        end

        # READER
        register_primitive('READER', 0, 0, 0) do |interp|
          interp.read_stream ? interp.open_files.key(interp.read_stream) || '' : ''
        end

        # WRITER
        register_primitive('WRITER', 0, 0, 0) do |interp|
          interp.write_stream ? interp.open_files.key(interp.write_stream) || '' : ''
        end

        # SETREADPOS
        register_primitive('SETREADPOS', 1, 1, 1) do |interp, pos|
          stream = interp.read_stream || $stdin
          stream.seek(interp.to_number(pos).to_i)
          nil
        end

        # SETWRITEPOS
        register_primitive('SETWRITEPOS', 1, 1, 1) do |interp, pos|
          stream = interp.write_stream || $stdout
          stream.seek(interp.to_number(pos).to_i)
          nil
        end

        # READPOS
        register_primitive('READPOS', 0, 0, 0) do |interp|
          stream = interp.read_stream || $stdin
          stream.pos rescue 0
        end

        # WRITEPOS
        register_primitive('WRITEPOS', 0, 0, 0) do |interp|
          stream = interp.write_stream || $stdout
          stream.pos rescue 0
        end

        # EOFP / EOF?
        register_primitive('EOFP', 0, 0, 0) do |interp|
          stream = interp.read_stream || $stdin
          stream.eof? ? 'true' : 'false'
        end
        register_alias('EOF?', 'EOFP')

        # FILEP / FILE?
        register_primitive('FILEP', 1, 1, 1) do |interp, filename|
          name = interp.full_path(interp.logo_to_word(filename))
          File.exist?(name) ? 'true' : 'false'
        end
        register_alias('FILE?', 'FILEP')
      end
    end
  end
end
