#!/usr/bin/env ruby
require 'redshift.rb'

include RedShift

class Observer < Component

  attr_accessor :b
  
  Normal = State.new :Normal
  
  attach({Normal => Normal}, Transition.new :observed_crash,
    proc {@save_dent = b.dent}, [],
    proc {print "Time #{world.clock_now}. Dent is #{@save_dent}\n"})
  
  attach({Normal => Exit}, Transition.new :exit,
    proc {world.clock_now == 10.5}, [],
    proc {print "\n\n ***** Observer departing.\n\n"})
  
  def set_defaults
    @state = Normal
  end
  
end

class Ball < Component

  attr_accessor :a
  
 	Falling = State.new :Falling
 	Rising = State.new :Rising
  
  attach [Falling, Rising], 
    [(AlgebraicFlow.new :y_err,
       "t = world.clock_now - @t_last
       (@y0 + @v0 * t + 0.5 * @a * t ** 2 - y).abs"),
     (RK4DifferentialFlow.new :y, "v"),
     (EulerDifferentialFlow.new :v, "a")]
  
  attach({Falling => Rising}, Transition.new :crash,
    proc {y <= 0},
    [Event.new(:dent)],
    proc {self.v = -v; @y0 = y; @v0 = v;
          @t_last = world.clock_now; @bounce_count += 1})
	
  attach({Rising => Falling}, Transition.new :peak,
    proc {v <= 0},
    [], nil)
  
  attach({Rising => Exit, Falling => Exit}, Transition.new :exit,
    proc {@bounce_count == 3},
    [], nil)
	
  def set_defaults
    @state = Falling
    @y0 = 100.0
    @v0 = 0.0
    @y = @y0
    @v = @v0
    @a = -9.8
    @t_last = 0
    @bounce_count = 0
  end
  
  def setup
  end
  
  def dent
   y.abs
  end
  
  def inspect
    sprintf "y = %8.4f, v = %8.4f, y_err = %8.6f%16s",
            @y, @v, y_err, @state.name
  end

end # class Ball

if __FILE__ == $0

w = World.new {
  time_step 0.01
}

b = w.create(Ball) {}
obs = w.create(Observer) {@b = b}

while w.components.size > 0 do
  t = w.clock_now
  if t == t.floor
    print "\nTime #{t}\n"
  end
  p b
  w.run
end

end
