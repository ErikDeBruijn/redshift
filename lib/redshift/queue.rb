module RedShift
  # a queue entry that contains multiple simultaneously enqueued objects
  # (same in both continuous and discrete time)
  class SimultaneousQueueEntries < Array; end

  class Queue
    # Owner of the queue.
    attr_reader :component
    
    def initialize component
      @q = []
      @clock = nil
      @step = nil
      @component = component
    end
    
    def push obj
      world = @component.world
      clock = world.clock
      step = world.discrete_step
      
      if clock == @clock and step == @step
        last = @q[-1]
        case last
        when SimultaneousQueueEntries
          last << obj
        when nil; raise "Internal error: expected simultaneous queue entry."
        else
          @q[-1] = SimultaneousQueueEntries[last, obj]
        end
      
      else
        was_empty = @q.empty?
        @clock = clock
        @step = step
        @q << obj
        @component.wake_for_queue if was_empty
      end
      
      self
    end
  
    alias << push
    
    # When popping from a queue, the result may be an instance
    # of SimultaneousQueueEntries, which should probably be handled specially.
    def pop
      @q.shift
    end
    
    def unpop obj
      @q.unshift obj
    end
    
    # Called from guard evaluation in step_discrete. Returns true if at least
    # one entry in the head of the queue matches _all_ of the conditions, which
    # may be Procs (called to return boolean) or any objects with #===.
    def head_matches(*conds)
      return false if @q.empty?
      head = @q[0]
      case head
      when SimultaneousQueueEntries
        head.any? do |head_item|
          item_matches conds, head_item
        end
      else
        item_matches conds, head
      end
    end
    
    def item_matches conds, item
      conds.all? do |cond|
        case cond
        when Proc
          cond.call(item)
        else
          cond === item
        end
      end
    end
  end
end
