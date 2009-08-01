#!/usr/bin/env ruby

require 'redshift/redshift'

include RedShift

# test setup clauses in world class and in world instance
# test World#started?

class World_1 < World
  setup { @x = 1 }; setup { @y = 2 }
  def initialize
    super {
      @z = 3
    }
    setup { @t = 4 }; setup { @u = 5 }
  end
  def assert_consistent_before test
    test.assert(!started?)
    test.assert_equal([nil,nil,3,nil,nil], [@x,@y,@z,@t,@u])
  end
  def assert_consistent_after test
    test.assert(started?)
    test.assert_equal([1,2,3,4,5], [@x,@y,@z,@t,@u])
  end
end

# test inheritance of setup clauses

class World_1_1 < World_1
  setup { @y = 2.1; @r = 6 }
  def initialize
    super
    setup { @u = 5.1; @s = 7 }
  end
  def assert_consistent_before test
    test.assert_equal([nil,nil,3,nil,nil,nil,nil], [@x,@y,@z,@t,@u,@r,@s])
  end
  def assert_consistent_after test
    test.assert_equal([1,2.1,3,4,5.1,6,7], [@x,@y,@z,@t,@u,@r,@s])
  end
end

# test world clock, time step, clock start, clock finish

class World_2 < World
  class Timer < Component
    flow {diff "t' = 1"}
  end
  
  def run
    super 1_000_000
  end

  def initialize(&block)
    super do
      time_step       1.01
      clock_start    90.001
      clock_finish  100
      block.call if block
    end
    
    setup do
      @timer = create(Timer) {self.t = 90.001}
    end
  end

  def assert_consistent_before test
    test.assert_equal(90.001, clock)
  end
  def assert_consistent_after test
    test.assert_equal_float(@timer.t, clock, 1.0E-13)
    test.assert_equal(100.101, clock)
  end
end

# test integer time step

class World_2_1 < World_2
  def initialize(&block)
    super do
      time_step    5
      block.call if block
    end
  end
  def assert_consistent_before test
    test.assert_equal(90.001, clock)
  end
  def assert_consistent_after test
    test.assert_equal_float(@timer.t, clock, 1.0E-13)
    test.assert_equal(100.001, clock)
  end
end

# test create and remove

if World.methods.include? :remove
  class World_3 < World
    setup do @x = create(Component) end
    def run
      super
      remove @x
    end

    def assert_consistent_after test
      test.assert_equal(0, size)
    end
  end
end

# test garbage collection

if World.methods.include? :remove
  class World_4 < World
    setup do
      @x = create(Component)
      5.times do create(Component) end
    end

    def run
      super
      @before_size = size
      garbage_collect
      @after_size = size
    end

    def assert_consistent_after test
      test.assert_equal(6, @before_size)
      test.assert((1..2).include? @after_size)
      ## After coding World::step_continuous in C, the last created component
      ## is still reachable for some reason.
    end
  end
end

# test zeno detection

class World_5 < World
  class Zeno < Component
    transition Enter => Enter
  end
  
  setup do create(Zeno) end
  
  def initialize
    super ### { zeno_limit 100 }
    self.zeno_limit = 100
  end
  
  def step_zeno zeno_counter
    @zeno_step_reached = true
  end
  
  def run
    super
  rescue => @e
  end
  
  def assert_consistent_after test
    test.assert_kind_of(ZenoError, @e)
    test.assert(@zeno_step_reached)
  end
end

# test "run 0"

class World_6 < World
  class Thing < Component
    state :A, :B
    default do
      start A
      @x = 0
    end
    flow A do
      diff "x' = 1"
    end
    transition A => B do
      guard {x < 0} # won't happen normally
    end
  end
  
  setup {@thing = create Thing}
  
  def run
    super 0 ## do_setup and step_discrete -- test this
    super 1
    super 0 ## should do nothing -- repeat and test this
    @thing.x = -1 # enables a guard
    super 0
  end
  
  def assert_consistent_before test
    test.assert_equal(0, size)
  end
  def assert_consistent_after test
    test.assert_equal(1, size)
    test.assert_equal(Thing::B, @thing.state)
  end
end

# test persistence

#class World_7 < World
#  def make_copy
#    filename = "test_world_persist.dat"
#    save filename
#    World.open filename   # copy of world (with the same name)
#  ensure
#    File.delete filename rescue SystemCallError
#  end
#  
#  class Thing < Component
#    attr_reader :x_start
#    state :A, :B, :C; default {start A}
#    setup do
#      @x_start = self.x = 123
#    end
#    transition A => B
#    transition B => C do
#      guard { x > 200 }
#    end
#    flow B, C do
#      diff "x' = 1"
#    end
#  end
#  
#  attr_accessor :thing
#  
#  setup do
#    @thing = create Thing
#  end
#  
#  def run n = nil
#    if n
#      super n
#    else
#      @start_copy = make_copy
#      super 0               # do_setup and step_discrete
#      @t0_copy = make_copy
#      super 1               # run the same world after saving
#      @t1_copy = make_copy
#      super 999
#      @t1000_copy = make_copy
#    end
#  end
#
#  def assert_consistent_after test
#    test.assert_equal(nil, @start_copy.thing)
#    test.assert_equal(Thing::B, @t0_copy.thing.state)
#    test.assert_equal(Thing::B, @t1_copy.thing.state)
#    test.assert_equal(Thing::C, @t1000_copy.thing.state)
#    test.assert_equal(Thing::C, thing.state)
#    
#    test.assert_equal(thing.x_start, @t0_copy.thing.x_start)
#    test.assert_equal(thing.x_start, @t1_copy.thing.x_start)
#    test.assert_equal(thing.x_start, @t1000_copy.thing.x_start)
#    test.assert_equal(thing.x_start, thing.x_start)
#    
#    x_t0    = thing.x_start
#    x_t1    = thing.x_start + time_step
#    x_t1000 = thing.x_start + 1000 * time_step  
#    
#    test.assert_equal_float(x_t0,     @t0_copy.thing.x, 1E-10)
#    test.assert_equal_float(x_t1,     @t1_copy.thing.x, 1E-10)
#    test.assert_equal_float(x_t1000,  @t1000_copy.thing.x, 1E-10)
#    test.assert_equal_float(x_t1000,  thing.x, 1E-10)
#    
#    # continue running with @t1_copy
#    @t1_copy.run 999
#    test.assert_equal(Thing::C, @t1_copy.thing.state)
#    test.assert_equal_float(x_t1000, @t1_copy.thing.x, 1E-10)
#  end
#end

puts "IGNORED SOME TESTS!"

=begin

tests:
  can you set time step et al during setup? No. Should this be allowed?
  run methods, debug tools

=end

#-----#

require 'runit/testcase'
require 'runit/cui/testrunner'
require 'runit/testsuite'
  
class TestWorld < RUNIT::TestCase
  
  def test_world
    testers = []
    ObjectSpace.each_object(Class) do |cl|
      if cl <= World and ## cl.instance_methods.grep /\Aassert_consistent/
         (cl.instance_methods.include? "assert_consistent_before" or
          cl.instance_methods.include? "assert_consistent_after")
        testers << cl.new
      end
    end
    
    for t in testers
      t.assert_consistent_before self if t.respond_to? :assert_consistent_before
      t.run
      t.assert_consistent_after self if t.respond_to? :assert_consistent_after
    end
  end
end

END {
  RUNIT::CUI::TestRunner.run(TestWorld.suite)
}
