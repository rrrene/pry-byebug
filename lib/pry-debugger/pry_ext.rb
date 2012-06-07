require 'pry'
require 'pry-debugger/processor'

class << Pry
  alias_method :start_existing, :start

  def start(target = TOPLEVEL_BINDING, options = {})
    if target.is_a?(Binding) && PryDebugger.check_file_context(target)
      # Wrap the processer around the usual Pry.start to catch navigation
      # commands.
      PryDebugger::Processor.new(options).run do
        start_existing(target, options)
      end
    else
      # No need for the tracer unless we have a file context to step through
      start_existing(target, options)
    end
  end
end