#!/usr/bin/env ruby

require 'redshift/redshift'

include RedShift

# Substitutability of algebraic flows (i.e. flows have function semantics)
# Dependencies of diff/euler/alg on alg, and alg on diff.

class FlowTestComponent < Component
  def finish test
  end
end

class Flow_Sub < FlowTestComponent
  s1 = "2*sin(u) + 1"
  s2 = "pow(u, 2) + 3 * u"
  
  f1 = proc { |v| s1.gsub(/u/,"(" + v + ")") }
  f2 = proc { |v| s2.gsub(/u/,"(" + v + ")") }
  
  flow {
    diff  "t'  = 1"
  
    alg   "x   = #{f1['t']}"
    alg   "xx  = #{f2['x']}"
    
    diff  "y0' = #{f2[f1['t']]}"
    diff  "y1' = #{f2['x']}"
    diff  "y2' = xx"
    
    euler "z0' = #{f2[f1['t']]}"
    euler "z1' = #{f2['x']}"
    euler "z2' = xx"
  }
  setup {
    self.t = 0
    self.y0 = self.y1 = self.y2 = self.z0 = self.z1 = self.z2 = 0
  }
  def assert_consistent test
    str = "at time #{t}"
    test.assert_equal_float(x, 2*sin(t) + 1, 0.000000001, str)
    test.assert_equal_float(xx, (2*sin(t) + 1)**2 + 3 * (2*sin(t) + 1),
      0.000000001, str)
    
    test.assert_equal_float(y0, y1, 0.000000001, str)
    test.assert_equal_float(y0, y2, 0.000000001, str)
    
    test.assert_equal_float(z0, z1, 0.000000001, str)
    test.assert_equal_float(z0, z2, 0.000000001, str)
  end
end


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
