module Tanuki

  # Tanuki::TemplateCompiler is used for, well, compiling templates.
  class TemplateCompiler

    class << self

      # Compiles a template from a given +src+ string to +ios+ for method +sym+ in class +klass+.
      def compile_template(ios, src, klass, sym)
        ios << "# encoding: #{src.encoding}\nclass #{klass}\ndef #{sym}_view(*args,&block)\nproc do|_,ctx|\n" \
          "if _has_tpl ctx,self.class,:#{sym}\nctx=_ctx(ctx)"
        last_state = compile(ios, src)
        ios << "\n_.('',ctx)" unless PRINT_STATES.include? last_state
        ios << "\nelse\n(_run_tpl ctx,self,:#{sym},*args,&block).(_,ctx)\nend\nend\nend\nend"
      end

      # Compiles code from a given +src+ string to +ios+.
      def compile(ios, src)
        state = :outer
        last_state = nil
        index = 0
        trim_newline = false
        code_buf = ''
        begin

          # Find out state for expected pattern
          if new_index = src[index..-1].index(pattern = expect_pattern(state))
            new_index += index
            match = src[index..-1].match(pattern)[0]
            new_state = next_state(state, match)
          else
            new_state = nil
          end

          # Process outer state (e.g. HTML or plain text)
          if state == :outer
            s = new_index ? src[index, new_index - index] : src[index..-1]
            if trim_newline && !s.empty?
              s[0] = '' if s[0] == "\n"
              trim_newline = false
            end
            if new_state == :code_skip
              code_buf << s.dup << match[0..-2]
              index = new_index + match.length
              next
            elsif not s.empty?
              ios << "\n_.(#{(code_buf << s).inspect},ctx)"
              code_buf = ''
            end
          end

          # Process current state, if there should be a state change
          if new_index
            unless state != :outer && new_state == :code_skip
              if new_state == :outer
                process_code_state(ios, code_buf << src[index...new_index], state)
                code_buf = ''
              end
              index = new_index + match.length
              trim_newline = true if (match == '-%>')
              last_state = state unless state == :code_comment
              state = new_state
            else
              code_buf << src[index...new_index] << '%>'
              index = new_index + match.length
            end
          end

        end until new_index.nil?
        last_state
      end

      private

      # Scanner states that output the evaluated result.
      PRINT_STATES = [:outer, :code_print]

      # Generates code for Ruby template bits from a given +src+ to +ios+ for a given +state+.
      def process_code_state(ios, src, state)
        src.strip!
        src.gsub!(/^[ \t]+/, '')
        case state
        when :code_line, :code_span then
          ios << "\n#{src}"
        when :code_print then
          ios << "\n_.((#{src}),ctx)"
        when :code_template then
          ios << "\n(#{src}).(_,ctx)"
        when :code_visitor
          inner_m = src.match(/^([^ \(]+)?(\([^\)]*\))?\s*(.*)$/)
          ios << "\n#{inner_m[1]}_result=(#{inner_m[3]}).(#{inner_m[1]}_visitor#{inner_m[2]},ctx)"
        when :l10n then
          localize(ios, src)
        end
      end

      # Returns the next expected pattern for a given +state+.
      def expect_pattern(state)
        case state
        when :outer then %r{^\s*%%?|<%[=!_#%]?|<l10n>}
        when :code_line then %r{\n|\Z}
        when :code_span, :code_print, :code_template, :code_visitor, :code_comment then %r{[-%]?%>}
        when :l10n then %r{<\/l10n>}
        end
      end

      # Returns the next state for a given +match+ and a given +state+.
      def next_state(state, match)
        case state
        when :outer then
          case match
          when /\A\s*%\Z/ then :code_line
          when /\A\s*%%\Z/ then :code_skip
          when '<%' then :code_span
          when '<%=' then :code_print
          when '<%!' then :code_template
          when '<%_' then :code_visitor
          when '<%#' then :code_comment
          when '<%%' then :code_skip
          when '<l10n>' then :l10n
          end
        when :code_line then :outer
        when :code_span, :code_print, :code_template, :code_visitor, :code_comment then
          case match
          when '%%>' then :code_skip
          else :outer
          end
        when :l10n then :outer
        end
      end

      # Generates localization code from +src+ to +ios+.
      def localize(ios, src)
        index = 0
        lngs = []
        ios << "\ncase ctx.best_language "
        code = StringIO.new
        while index = src.index(/<[a-z]{2}>/, index)
          lngs << (lng = src[index + 1, 2].to_sym)
          if end_index = src.index(/<\/#{lng}>/, index += 4)
            code << "\nwhen #{lng.inspect} then"
            compile(code, src[index...end_index])
            index = end_index + 5
          end
        end
        ios << "#{lngs.inspect.gsub(/ /, '')}#{code.string}\nend"
      end

    end # class << self

  end # TemplateCompiler

end # Tanuki