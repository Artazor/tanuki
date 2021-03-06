module Tanuki

  # Tanuki::Loader deals with framework paths resolving, and object and template loading.
  class Loader

    class << self

      # Returns the path to a source file in +root+ containing class +klass+.
      def class_path(klass, root)
        path = const_to_path(klass, root)
        File.join(path, path.match("#{File::SEPARATOR}([^#{File::SEPARATOR}]*)$")[1] << '.rb')
      end

      # Returns the path to a source file containing class +klass+.
      # Seatches across all common roots.
      def combined_class_path(klass)
        class_path(klass, @app_root ||= combined_app_root)
      end

      # Returns a glob pattern of all common roots.
      def combined_app_root
        local_app_root = File.expand_path(File.join('..', '..', '..', 'app'), __FILE__)
        app_root = "{#{context_app_root = @context.app_root},#{@context.gen_root}"
        app_root << ",#{local_app_root}" if local_app_root != context_app_root
        app_root << '}'
      end

      # Assigns a context to Tanuki::Loader.
      # This context should have common framework paths defined in it.
      def context=(ctx)
        @context = ctx
      end

      # Checks if +templates+ contain a compiled template +sym+ for class +klass+.
      def has_template?(templates, klass, sym)
        templates.include? "#{klass}##{sym}"
      end

      # Runs template +sym+ with optional +args+ and +block+ from object +obj+.
      #
      # Template is recompiled from source on two conditions:
      # * template source modification time is older than compiled template modification time,
      # * Tanuki::TemplateCompiler source modification time is older than compiled template modification time.
      def run_template(templates, obj, sym, *args, &block)
        owner, st_path = *template_owner(obj.class, sym)
        if st_path
          ct_path = compiled_template_path(owner, sym)
          ct_file_exists = File.file?(ct_path)
          ct_file_mtime = ct_file_exists ? File.mtime(ct_path) : nil
          st_file = File.new(st_path, 'r:UTF-8')

          # Find out if template refresh is required
          if !ct_file_exists || st_file.mtime > ct_file_mtime || File.mtime(COMPILER_PATH) > ct_file_mtime
            no_refresh = compile_template(st_file, ct_path, ct_file_mtime, owner, sym)
          else
            no_refresh = true
          end

          # Load template
          method_name = "#{sym}_view".to_sym
          owner.instance_eval do
            unless (method_exists = instance_methods(false).include? method_name) && no_refresh
              remove_method method_name if method_exists
              load ct_path
            end
          end

          # Register template in cache
          templates["#{owner}##{sym}"] = nil
          templates["#{obj.class}##{sym}"] = nil

          obj.send(method_name, *args, &block)
        else
          raise "undefined template `#{sym}' for #{obj.class}"
        end
      end

      private

      # Path to Tanuki::TemplateCompiler for internal use.
      COMPILER_PATH = File.expand_path(File.join('..', 'template_compiler.rb'), __FILE__)

      # Extension glob for template files.
      TEMPLATE_EXT = '.t{html,txt}'

      # Compiles template +sym+ from +owner+ class using source in +st_file+ to +ct_path+.
      # Compilation is only done if destination file modification time has not changed
      # (is equal to +ct_file_mtime+) since file locking was initiated.
      def compile_template(st_file, ct_path, ct_file_mtime, owner, sym)
        no_refresh = true

        # Lock template source to avoid race condition
        st_file.flock(File::LOCK_EX)

        # Compile, if template still needs compiling on lock release
        if !File.file?(ct_path) || File.mtime(ct_path) == ct_file_mtime
          no_refresh = false
          ct_dir = File.dirname(ct_path)
          FileUtils.mkdir_p(ct_dir) unless File.directory?(ct_dir)
          File.open(tmp_ct_path = ct_path + '~', 'w:UTF-8') do |ct_file|
            TemplateCompiler.compile_template(ct_file, st_file.read, owner, sym)
          end
          FileUtils.mv(tmp_ct_path, ct_path)
        end

        # Release lock
        st_file.flock(File::LOCK_UN)

        no_refresh
      end

      # Returns the path to a compiled template file containing template +method_name+ for class +klass+.
      def compiled_template_path(klass, method_name)
        File.join(const_to_path(klass, @context.gen_root), method_name.to_s << '.tpl.rb')
      end

      # Transforms a given constant +klass+ to a path with a given +root+.
      def const_to_path(klass, root)
        File.join(root, klass.to_s.split('_').map {|item| item.gsub(/(?!^)([A-Z])/, '_\1') }.join(File::SEPARATOR).downcase)
      end

      # Finds the direct template +method_name+ owner among ancestors of class +klass+.
      def template_owner(klass, method_name)
        method_file = method_name.to_s << TEMPLATE_EXT
        klass.ancestors.each do |ancestor|
          files = Dir.glob(File.join(const_to_path(ancestor, @app_root ||= combined_app_root), method_file))
          return ancestor, files[0] unless files.empty?
        end
        [nil, nil]
      end

    end # class << self

  end # Path

end # Tanuki