require 'pry'
require 'pry/byebug/breakpoints'

#
# Main Pry class.
#
# We're going to add to it custom breakpoint commands for Pry-Byebug
#
class Pry
  BreakpointCommands = CommandSet.new do
    create_command 'break' do
      description 'Set or edit a breakpoint.'

      banner <<-BANNER
        Usage:   break <METHOD | FILE:LINE | LINE> [if CONDITION]
                 break --condition N [CONDITION]
                 break [--show | --delete | --enable | --disable] N
                 break [--delete-all | --disable-all]
        Aliases: breakpoint

        Set a breakpoint. Accepts a line number in the current file, a file and
        line number, or a method, and an optional condition.

        Pass appropriate flags to manipulate existing breakpoints.

        Examples:

          break SomeClass#run         Break at the start of `SomeClass#run`.
          break Foo#bar if baz?       Break at `Foo#bar` only if `baz?`.
          break app/models/user.rb:15 Break at line 15 in user.rb.
          break 14                    Break at line 14 in the current file.

          break --condition 4 x > 2   Add/change condition on breakpoint #4.
          break --condition 3         Remove the condition on breakpoint #3.

          break --delete 5            Delete breakpoint #5.
          break --disable-all         Disable all breakpoints.

          break                       List all breakpoints.
          break --show 2              Show details about breakpoint #2.
      BANNER

      def options(opt)
        defaults = { argument: true, as: Integer }

        opt.on :c, :condition, 'Change condition of a breakpoint.', defaults
        opt.on :s, :show, 'Show breakpoint details and source.', defaults
        opt.on :D, :delete, 'Delete a breakpoint.', defaults
        opt.on :d, :disable, 'Disable a breakpoint.', defaults
        opt.on :e, :enable, 'Enable a disabled breakpoint.', defaults
        opt.on :'disable-all', 'Disable all breakpoints.'
        opt.on :'delete-all', 'Delete all breakpoints.'
      end

      def process
        all = %w(condition show delete disable enable disable-all delete-all)
        all.each do |option|
          next unless opts.present?(option)

          method_name = "process_#{option.gsub('-', '_')}"
          return send(method_name)
        end

        new_breakpoint unless args.empty?
      end

      %w(delete disable enable).each do |command|
        define_method(:"process_#{command}") do
          Byebug::Breakpoints.send(command, opts[command])
          run 'breakpoints'
        end
      end

      %w(disable-all delete-all).each do |command|
        method_name = command.gsub('-', '_')
        define_method(:"process_#{method_name}") do
          Byebug::Breakpoints.send(method_name)
          run 'breakpoints'
        end
      end

      def process_show
        print_full_breakpoint(Byebug::Breakpoints.find_by_id(opts[:show]))
      end

      def process_condition
        expr = args.empty? ? nil : args.join(' ')
        Byebug::Breakpoints.change(opts[:condition], expr)
      end

      def new_breakpoint
        place = args.shift
        condition = args.join(' ') if 'if' == args.shift

        bp =
          case place
          when /^(\d+)$/
            errmsg = 'Line number declaration valid only in a file context.'
            PryByebug.check_file_context(target, errmsg)

            file, lineno = target.eval('__FILE__'), Regexp.last_match[1].to_i
            Byebug::Breakpoints.add_file(file, lineno, condition)
          when /^(.+):(\d+)$/
            file, lineno = Regexp.last_match[1], Regexp.last_match[2].to_i
            Byebug::Breakpoints.add_file(file, lineno, condition)
          when /^(.*)[.#].+$/  # Method or class name
            if Regexp.last_match[1].strip.empty?
              errmsg = 'Method name declaration valid only in a file context.'
              PryByebug.check_file_context(target, errmsg)
              place = target.eval('self.class.to_s') + place
            end
            Byebug::Breakpoints.add_method(place, condition)
          else
            fail(ArgumentError, 'Cannot identify arguments as breakpoint')
          end

        print_full_breakpoint(bp)
      end
    end
    alias_command 'breakpoint', 'break'

    create_command 'breakpoints' do
      description 'List defined breakpoints.'

      banner <<-BANNER
        Usage:   breakpoints [OPTIONS]
        Aliases: breaks

        List registered breakpoints and their current status.
      BANNER

      def options(opt)
        opt.on :v, :verbose, 'Print source around each breakpoint.'
      end

      def process
        unless Byebug::Breakpoints.count > 0
          errmsg = 'No breakpoints defined.'
          return output.puts text.bold(errmsg)
        end

        if opts.verbose?
          Byebug::Breakpoints.each { |b| print_full_breakpoint(b) }
        else
          output.puts
          print_breakpoints_header
          Byebug::Breakpoints.each { |b| print_short_breakpoint(b) }
          output.puts
        end
      end
    end
    alias_command 'breaks', 'breakpoints'

    helpers do
      #
      # Print out full information about a breakpoint.
      #
      # Includes surrounding code at that point.
      #
      def print_full_breakpoint(breakpoint)
        output.print text.bold("Breakpoint #{breakpoint.id}: ")
        output.print "#{breakpoint} "
        output.print breakpoint.enabled? ? '(Enabled)' : '(Disabled)'
        output.puts ' :'
        if (expr = breakpoint.expr)
          output.puts "#{text.bold('Condition:')} #{expr}"
        end
        output.puts
        output.puts breakpoint.source_code.with_line_numbers.to_s
        output.puts
      end

      #
      # Print out concise information about a breakpoint.
      #
      def print_short_breakpoint(breakpoint)
        output.printf "%#{max_width}d  ", breakpoint.id
        output.print breakpoint.enabled? ? 'Yes      ' : 'No       '
        output.print breakpoint.to_s
        output.print " (if #{breakpoint.expr})" if breakpoint.expr
        output.puts
      end

      #
      # Prints a header for the breakpoint list.
      #
      def print_breakpoints_header
        header = "#{' ' * (max_width - 1)}#  Enabled  At "

        output.puts text.bold(header)
        output.puts text.bold('-' * header.size)
      end

      #
      # Max width of breakpoints id column
      #
      def max_width
        [Math.log10(Byebug::Breakpoints.count).ceil, 1].max
      end
    end
  end

  Pry.commands.import(BreakpointCommands)
end
