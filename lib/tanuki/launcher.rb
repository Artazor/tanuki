module Tanuki
  class Launcher
    def initialize(ctrl)
      @ctrl = ctrl
    end

    def each(&block)
      @ctrl.index_view.call(proc {|out| block.call(out.to_s) })
    end
  end
end