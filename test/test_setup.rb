#!/usr/bin/env ruby

require 'redshift/redshift'

include RedShift

class SetupTestComponent < Component
  attr_accessor :x
end

# setup and defaults should both be able to set @state

class Setup_1a < SetupTestComponent
  state :A
  default { start A }
  def assert_consistent test
    test.assert_equal(A, state)
  end
end

class Setup_1b < SetupTestComponent
  state :A
  setup { start A }
  def assert_consistent test
    test.assert_equal(A, state)
  end
end

# defaults happen before setup

class Setup_2 < SetupTestComponent
  state :A, :B
  default { start A }
  setup { start B }
  def assert_consistent test
    test.assert_equal(B, state)
  end
end

# create block happens after defaults, before setup

class Setup_3a < SetupTestComponent
  defaults { self.x = 0 }
  def assert_consistent test
    test.assert_equal(1, x)
  end
end

class Setup_3b < SetupTestComponent
  setup { self.x = 2 }
  def assert_consistent test
    test.assert_equal(2, x)
  end
end

# multiple setup and defaults blocks chain after each other

class Setup_4a < SetupTestComponent
  attr_accessor :y, :z
  defaults { self.y = 3 }
  defaults { self.z = 4 }
  def assert_consistent test
    test.assert_equal([3,4], [y,z])
  end
end

class Setup_4b < SetupTestComponent
  attr_accessor :y, :z
  setup { self.y = 3 }
  setup { self.z = 4 }
  def assert_consistent test
    test.assert_equal([3,4], [y,z])
  end
end

#-----#

require 'runit/testcase'
require 'runit/cui/testrunner'
require 'runit/testsuite'

class TestSetup < RUNIT::TestCase
  
  def setup
    @world = World.new { time_step 0.1 }
  end
  
  def teardown
    @world = nil
  end
  
  def test_setup
    testers = []
    ObjectSpace.each_object(Class) do |cl|
      if cl <= SetupTestComponent and
         cl.instance_methods.include? "assert_consistent"
        testers << @world.create(cl) { self.x = 1 }
      end
    end
    
    for t in testers
      t.assert_consistent self
    end
  end
end

END {
  RUNIT::CUI::TestRunner.run(TestSetup.suite)
}
