#!/usr/bin/env ruby

require 'redshift/redshift'

include RedShift

class FlowTestComponent < Component
  def finish test
  end
end

# Empty flows are constant.

class Flow_Empty < FlowTestComponent
  continuous :x
  setup { self.x = 5 }
  def assert_consistent test
    test.assert_equal_float(5, x, 0.0000000000001)
  end
end

# Make sure timers work!

class Flow_Euler < FlowTestComponent
  flow { euler "t' = 1" }
  setup { self.t = 0 }
  def assert_consistent test
    test.assert_equal_float(world.clock, t, 0.0000000001)
  end
end

# Alg flows.

class Flow_Alg < FlowTestComponent
  flow { alg "f = 1", "g = f + 2" }
  def assert_consistent test
    test.assert_equal_float(1, f, 0.0000000001)
    test.assert_equal_float(3, g, 0.0000000001)
  end
end

# Trig functions.

class Flow_Sin < FlowTestComponent
  flow { diff  "y' = y_prime", "y_prime' = -y" }
  setup { self.y = 0; self.y_prime = 1 }
  def assert_consistent test
    test.assert_equal_float(sin(world.clock), y, 0.000000001)
    ## is this epsilon ok? how does it compare with cshift?
  end
end

# Exp functions.

class Flow_Exp < FlowTestComponent
  flow { diff  "y' = y" }
  setup { self.y = 1 }
  def assert_consistent test
    test.assert_equal_float(exp(world.clock), y, 0.0001)
  end
end

# Polynomials.

class Flow_Poly < Flow_Euler    # note use of timer t from Flow_Euler
  flow {
    alg   "poly = -6 * pow(t,3) + 1.2 * pow(t,2) - t + 10"
    diff  "y' = y1", "y1' = y2", "y2' = y3", "y3' = 0"
  }
  setup { self.y = 10; self.y1 = -1; self.y2 = 1.2 * 2; self.y3 = -6 * 3 * 2 }
  def assert_consistent test
    test.assert_equal_float(poly, y, 0.000000001, "at time #{world.clock}")
  end
end

# test for detection of circularity and assignment to algebraically
# defined vars

class Flow_AlgebraicErrors < FlowTestComponent
  flow {
    alg "x = y"
    alg "y = x"
    alg "z = 1"
  }
  
  def assert_consistent test
    return if world.clock > 1
    test.assert_exception(RedShift::CircularDefinitionError) {y}
    test.assert_exception(RedShift::AlgebraicAssignmentError) {self.z = 2}
  end
end

## TO DO ##
=begin
 
 varying time step (dynamically?)
 
 handling of syntax errors
 
=end

###class Flow_MixedType < FlowTestComponent
###  flow  {
###    euler "w' = 4"
###    diff  "x' = w"
###    diff  "y' = 4"
###    diff  "z' = y"  ### fails if these are more complex than just w or y
###  }
###  setup { self.w = self.y = 0; self.x = self.z = 0 }
###  def assert_consistent test
###    test.assert_equal_float(x, z, 0.001, "at time #{world.clock}")
###  end
###end


#-----#

require 'runit/testcase'
require 'runit/cui/testrunner'
require 'runit/testsuite'

class TestFlow < RUNIT::TestCase
  
  def setup
    @world = World.new { time_step 0.01; self.zeno_limit = 100 }
  end
  
  def teardown
    @world = nil
  end
  
  def test_flow
    testers = []
    ObjectSpace.each_object(Class) do |cl|
      if cl <= FlowTestComponent and
         cl.instance_methods.include? "assert_consistent"
        testers << @world.create(cl)
      end
    end
    
    testers.each { |t| t.assert_consistent self }
    @world.run 1000 do
      testers.each { |t| t.assert_consistent self }
    end
    testers.each { |t| t.finish self }
  end
end

END {
  Dir.mkdir "tmp" rescue SystemCallError
  Dir.chdir "tmp"

  RUNIT::CUI::TestRunner.run(TestFlow.suite)

#  require 'plot/plot'
#  Plot.new ('gnuplot') {
#    add Flow_Reconfig::Y, 'title "y" with lines'
#    add Flow_Reconfig::Y1, 'title "y1" with lines'
#    add Flow_Reconfig::Y2, 'title "y2" with lines'
#    add Flow_Reconfig::Y3, 'title "y3" with lines'
#    show
#    pause 5
#  }

}
