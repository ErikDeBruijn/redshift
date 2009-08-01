#!/usr/bin/env ruby

require 'redshift/redshift'

include RedShift

=begin

This file runs tests that have to be done without the presence of other objects in the world. Each test is performed in a separate world.

=end

class DiscreteIsolatedTestComponent < Component
  def initialize(*args)
    super
    @t = world.clock
  end
end

# transitions with no body keep the discrete step alive

class DiscreteIsolated_1 < DiscreteIsolatedTestComponent
  state :A, :B
  flow A do
    diff "x' = 1"
  end
  transition Enter => A, A => B
  def assert_consistent test
    test.assert_equal(B, state)
    test.assert_equal_float(0, x, 1.0E-20)
  end
end

# transitions with just a guard keep the discrete step alive

class DiscreteIsolated_2 < DiscreteIsolatedTestComponent
  state :A, :B
  flow A do
    diff "x' = 1"
  end
  transition Enter => A, A => B do
    guard {true}
  end
  def assert_consistent test
    test.assert_equal(B, state)
    test.assert_equal_float(0, x, 1.0E-20)
  end
end


#-----#

require 'runit/testcase'
require 'runit/cui/testrunner'
require 'runit/testsuite'

class TestDiscrete < RUNIT::TestCase
  
  def setup
    @world = World.new { time_step 0.1 }
  end
  
  def teardown
    @world = nil
  end
  
  def test_discrete_isolated
    testers = []
    ObjectSpace.each_object(Class) do |cl|
      if cl <= DiscreteIsolatedTestComponent and
         cl.instance_methods.include? "assert_consistent"
        world = World.new { time_step 0.1 }
        testers << [world, world.create(cl)]
      end
    end
    
    for w,t in testers
      w.run
      t.assert_consistent self
    end
  end
end

END {
  Dir.mkdir "tmp" rescue SystemCallError
  Dir.chdir "tmp"

  RUNIT::CUI::TestRunner.run(TestDiscrete.suite)
}
