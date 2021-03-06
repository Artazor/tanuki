module Tanuki

  # Tanuki::Application is the starting point for all framework applications.
  # It contains core application functionality like configuration, request handling and view management.
  class Application

    @context = (Loader.context = Context).child
    @rack_middleware = []

    class << self

      # Initializes application settings using configuration for environment +env+.
      # These include settings for server, context, and middleware.
      # Returns true, if configuration is successful.
      def configure(env)
        @environment = env
        begin
          default_root = File.expand_path(File.join('..', '..', '..'), __FILE__)
          @cfg = Configurator.new(Context, pwd = Dir.pwd)

          # Configure in default root (e.g. gem root)
          if pwd != default_root
            @cfg.config_root = File.join(default_root, 'config')
            @cfg.load_config(([:development, :production].include? env) ? :"#{env}_application" : :common_application)
          end

          # Configure in application root
          @cfg.config_root = File.join(pwd, 'config')
          @cfg.load_config :"#{env}_application", pwd != default_root

          return true
        rescue NameError => e
          if e.name =~ /\AA-Z/
            raise NameError, "missing class or module for constant `#{e.name}'", e.backtrace
          else
            raise e
          end
        end
        false
      end

      # Add utilized middleware to a given Rack::Builder instance +rack_builder+.
      def configure_middleware(rack_builder)
        @rack_middleware.each {|item| rack_builder.use(item[0], *item[1], &item[2]) }
      end

      # Removes all occurences of a given +middleware+ from the Rack middleware pipeline.
      def discard(middleware)
        @rack_middleware.delete_if {|item| item[0] == middleware }
      end

      # Returns current environment +Symbol+, if application is configured.
      # Returns +nil+ otherwise.
      def environment
        @environment ||= nil
      end

      # Runs the application with current settings.
      def run
        configure_middleware(rack_builder = Rack::Builder.new)
        rack_builder.run(rack_app)

        # Choose and start a Rack handler
        @context.running_server = available_server
        @context.running_server.run rack_builder.to_app, :Host => @context.host, :Port => @context.port do |server|
          [:INT, :TERM].each {|sig| trap(sig) { (server.respond_to? :stop!) ? server.stop! : server.stop } }
          puts "A#{'n' if @environment =~ /\A[aeiou]/} #{@environment} Tanuki appears! Press Ctrl-C to set it free.",
            "You used #{@context.running_server.name.gsub(/.*::/, '')} at #{@context.host}:#{@context.port}."
        end
      end

      # Adds a given +middleware+ with optional +args+ and +block+ to the Rack middleware pipeline.
      def use(middleware, *args, &block)
        @rack_middleware << [middleware, args, block]
      end

      # Adds a template visitor +block+. This +block+ must return a +Proc+.
      #
      #  visitor :escape do
      #    s = ''
      #    proc {|out| s << CGI.escapeHTML(out.to_s) }
      #  end
      #  visitor :printf do |format|
      #    s = ''
      #    proc {|out| s << format % out.to_s }
      #  end
      #
      # It can later be used in a template via the visitor syntax.
      #
      #  <%_escape escaped_view %>
      #  <%_printf('<div>%s</div>') formatted_view %>
      def visitor(sym, &block)
        BaseBehavior.instance_eval { define_method "#{sym}_visitor".to_sym, &block }
      end

      private

      # Returns the first available server from a server list in the current context.
      def available_server
        @context.server.each do |server_name|
          begin
            return Rack::Handler.get(server_name.downcase)
          rescue LoadError
          rescue NameError
          end
        end
        raise "servers #{@context.server.join(', ')} not found"
      end

      # Returns an array of template outputs for controller +ctrl+ in context +request_ctx+.
      def build_body(ctrl, request_ctx)
        arr = []
        Launcher.new(ctrl, request_ctx).each &proc {|out| arr << out.to_s }
      end

      # Returns a Rack app block for Rack::Builder.
      # This block is passed a request environment and returns and array of three elements:
      # * a response status code,
      # * a hash of headers,
      # * an iterable body object.
      # It is run on each request.
      def rack_app
        ctx = @context
        proc do |env|
          request_ctx = ctx.child
          request_ctx.templates = {}

          # If there are trailing slashes in path, don't dispatch
          if match = env['PATH_INFO'].match(/^(.+)(?<!\$)\/$/)

            # Remove trailing slash in the path and redirect
            loc = match[1]
            loc << "?#{env['QUERY_STRING']}" unless env['QUERY_STRING'].empty?
            [301, {'Location' => loc, 'Content-Type' => 'text/html; charset=utf-8'}, []]

          else

            # Dispatch controller chain for the current path
            request_ctx.env = env
            result = ::Tanuki::ControllerBehavior.dispatch(request_ctx, ctx.i18n ? ::Tanuki::I18n : ctx.root_page,
              Rack::Utils.unescape(env['PATH_INFO']).force_encoding('UTF-8'))

            # Handle dispatch result
            case result[:type]
            when :redirect then
              [302, {'Location' => result[:location], 'Content-Type' => 'text/html; charset=utf-8'}, []]
            when :page then
              [200, {'Content-Type' => 'text/html; charset=utf-8'}, build_body(result[:controller], request_ctx)]
            else
              [404, {'Content-Type' => 'text/html; charset=utf-8'}, build_body(result[:controller], request_ctx)]
            end

          end # if

        end
      end

    end # class << self

  end # Application

end # Tanuki
