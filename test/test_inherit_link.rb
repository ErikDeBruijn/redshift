#!/usr/bin/env ruby

require 'redshift/redshift'

include RedShift

class LinkTestComponent < Component
  class Foo < Component; end
  link :foo => Foo
end

class Link_1 < LinkTestComponent
  setup {self.foo = create Foo}
  def assert_consistent test
    test.assert_equal(LinkTestComponent::Foo, foo.type)
  end
end

class Link_2 < LinkTestComponent
  class Bar < Foo; end
###  link :foo => Bar ### ==> "already exists"
end

# test forward references
class Link_FwdRef < Component
  link :fwd => :FwdRefClass
  setup {self.fwd = create FwdRefClass}
  def assert_consistent test
    test.assert_equal(1, fwd.x)
  end
end

class FwdRefClass < Component
  flow {alg "x = 1"}
end

#-----#

require 'runit/testcase'
require 'runit/cui/testrunner'
require 'runit/testsuite'

class TestInheritLink < RUNIT::TestCase
  
  def setup
    @world = World.new { time_step 0.1 }
  end
  
  def teardown
    @world = nil
  end
  
  def test_inherit_link
    testers = []
    ObjectSpace.each_object(Class) do |cl|
      if cl <= LinkTestComponent and
         cl.instance_methods.include? "assert_consistent"
        testers << @world.create(cl)
      end
    end
    
    testers.each { |t| t.assert_consistent self }
    @world.run 100
    testers.each { |t| t.assert_consistent self }
  end
end

END {
  RUNIT::CUI::TestRunner.run(TestInheritLink.suite)
}
