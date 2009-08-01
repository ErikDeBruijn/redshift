#!/usr/bin/env ruby

require 'redshift/redshift'

include RedShift

#-- Transition-specific test classes --#

class TransTestComponent < Component
  def initialize(*args)
    super
    @t = world.clock
  end
end

#     --------------------
#     Per edge granularity

class Trans_1 < TransTestComponent
  defaults do
    @x = 0
  end
  
  state :A, :B, :C, :D
  transition Enter => A  
  transition A => B, B => C, C => D do
    name :foo
    action { @x += 1 }
  end
end

class Trans_1_1 < Trans_1
  transition B => C do
    name :foo
    action { }            # override one of several transitions
  end
  def assert_consistent test
    test.assert_equal(state == Enter ? 0 : 2, @x)
  end
end

class Trans_1_2 < Trans_1
  state :F                # E is the constant 2.718281828
  transition D => F do
    action { @x += 1 }    # add one new transition
  end
  def assert_consistent test
    test.assert_equal(state == Enter ? 0 : 4, @x)
  end
end

class Trans_1_3 < Trans_1
  transition B => C do
    name :foo
    guard { false }
    action { 1/0 }        # this shouldn't happen
  end
end

class Trans_1_3_1 < Trans_1_3
  transition B => C do
    name :foo
    # neither the guard nor the action of the superclass is inherited
  end
  def assert_consistent test
    test.assert_equal(state == Enter ? 0 : 2, @x)
  end
end

#     ----------------------------
#     Redundant state declarations

### -- obsolete? --
###class Trans_2 < TransTestComponent
###  state :A, :B, :C, :D
###  transition Enter => A, A => B, C => D
###end
###
###class Trans_2_1 < Trans_2
###  transition B => C
###  def assert_consistent test
###    test.assert(state == Enter || state == D,
###                "State is #{state.name}, not Enter or D")
###  end
###end

#     ------
#     Events

# events are inherited

class Trans_3 < TransTestComponent
  state :A
  transition Enter => A do
    event :e => "fred"
  end
end

class Trans_3_1 < Trans_3
  def assert_consistent test
    # just so it gets created
  end
end

class Trans_3a < TransTestComponent
  state :A
  transition Enter => A do
    guard {
      ObjectSpace.each_object(Trans_3_1) {|@t|}
      @t.e == "fred"
    }
    action { @worked = true }
  end
  def assert_consistent test
    test.assert(world.clock == 0 || @worked)
  end
end

#-----#

require 'runit/testcase'
require 'runit/cui/testrunner'
require 'runit/testsuite'

class TestInheritTrans < RUNIT::TestCase
  
  def setup
    @world = World.new { time_step 0.1 }
  end
  
  def teardown
    @world = nil
  end
  
  def test_inherit_trans
    testers = []
    ObjectSpace.each_object(Class) do |cl|
      if cl <= TransTestComponent and
         cl.instance_methods.include? "assert_consistent"
        testers << @world.create(cl)
      end
    end
    
    for t in testers
      assert_equal(RedShift::Enter, t.state)
      t.assert_consistent self
    end
    
    @world.run 100
    
    for t in testers
      assert(RedShift::Enter != t.state, "#{t.type} didn't leave Enter!")
      t.assert_consistent self
    end
  end
end

END {
  Dir.mkdir "tmp" rescue SystemCallError
  Dir.chdir "tmp"

  RUNIT::CUI::TestRunner.run(TestInheritTrans.suite)
}
