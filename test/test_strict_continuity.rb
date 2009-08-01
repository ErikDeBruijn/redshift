#!/usr/bin/env ruby

require 'redshift'

include RedShift

# Tests strictly continuous and strictly constant variables. Tests strict
# link variables.
#
# - tests that guard optimization works: guards are eval-ed once per step
#
# - tests exceptions raised by assigning to strict vars
#
# - tests exception raised by a transition to a state that algebraically
#   defines a variable in an inconsistent way
#
# [Note: exceptions caused by algebraically defining a strict var
#  in terms of a non-strict var are caught at compile time. See
#  test_strictness_error.rb. Similarly, a reset on a strict var can
#  be caught at compile time. See test_strict_reset_error.rb.]

class SCWorld < World
  def num_checks
    @num_checks ||= Hash.new do |h,comp|
      h[comp] = Hash.new do |h1,trans|
        h1[trans] = 0
      end
    end
  end
  
  def hook_eval_guard(comp, guard, enabled, trans, dest)
    num_checks[comp][trans.name] += 1
  end
end

class TestComponent < Component
  def finish(test); end
end

class C < Component
  strictly_constant :y
  setup do
    self.y = 1
  end
end

class A < TestComponent
  strictly_continuous :x
  strict_link :c => C
  
  flow do
    diff "x' = c.y"
  end
  
  setup do
    self.c = create C
  end
  
  transition Enter => Exit do
    name "t1"
    guard " x > 0.50 "
  end

  transition Enter => Exit do
    name "t2"
    guard " x > 0.73 "
  end
  
  def assert_consistent(test)
    case state
    when Enter
      # Should not check the guard more than once per step, or so.
      num_checks = world.num_checks[self]
      t1_count = num_checks["t1"]
      t2_count = num_checks["t2"]
      
      step_count = world.step_count
      step_count = (step_count == 0 ? step_count : step_count + 1)
      # This accounts for the fact that step_discrete is called an "extra"
      # time at the start of one call to World#step or #evolve.
      
      test.assert_equal(step_count, t1_count)
      test.assert_equal(step_count, t2_count)
      
    when Exit
      ## we really only need to do these tests once...
      old_x = x
      old_c = c
      old_c_y = c.y
      
      test.assert_raises(RedShift::StrictnessError) do
        self.x = x
      end
    
      test.assert_raises(RedShift::StrictnessError) do
        self.c = c
      end
    
      test.assert_raises(RedShift::StrictnessError) do
        c.y = c.y
      end
      
      # strictness has a backdoor...
      begin
        self.x = 123
      rescue RedShift::StrictnessError
      end
      test.assert_equal(123, x)
      
      begin
        self.c = nil
      rescue RedShift::StrictnessError
      end
      test.assert_equal(nil, c)
      
      (self.x = old_x) rescue nil
      (self.c = old_c) rescue nil
      (c.y = old_c_y) rescue nil
    end
  end
end

# This component exists to give the A instance a chance to make too many
# guard checks.
class B < TestComponent
  state :S, :T, :U
  setup do
    start S
  end
  
  flow S do
    diff "time' = 1"
  end
  
  transition S => T do
    guard "time > 0"
    reset :time => 0 # so we do it again next timestep
  end
  
  transition T => U
  
  transition U => S do
    action do
      @awake = world.size - world.strict_sleep.size - world.inert.size
    end
  end

  def assert_consistent(test)
    if @awake
      test.assert_equal(1, @awake) # just the B
    end
  end
end

class D1 < Component
  strictly_continuous :x
  setup do
    self.x = 1
  end
  
  state :Inconsistent
  
  flow Inconsistent do
    algebraic " x = 2 "
  end
  
  transition Enter => Inconsistent do
    guard "x > 0"
  end
end

class D2 < Component
  strictly_continuous :x
  setup do
    self.x = 1
  end
  
  state :Inconsistent
  
  flow Inconsistent do
    algebraic " x = 2 "
  end
  
  transition Enter => Inconsistent do
    guard {x > 0}
  end
end

# test that lazily evaluated alg exprs get evaled correctly on demand
class Lazy < TestComponent
  strictly_continuous :x, :y
  # z is not strict, so that the second test below is meaningful
  state :Test1, :Test2, :Test3

  flow Test1, Test2 do
    diff " x' = 1 "
    alg  " y  = 2*x "
    alg  " z  = y "
  end
  
  transition Test1 => Test2 do
    guard "x >= 0.5"
    action {@x = x; @test = y}
  end

  transition Test2 => Test3 do
    guard "x >= 0.7"
    action {@x = x; @test = z}
      # indirect eval of y from z's alg expr is different from
      # using the y reader method.
  end

  def assert_consistent(test)
    case state
    when Test1, Test2
      test.assert_in_delta(2 * @x, @test, 1.0E-10)
    end
  end
end

#-----#

require 'test/unit'

class TestStrictContinuity < Test::Unit::TestCase
  
  def setup
    @world = SCWorld.new
    @world.time_step = 0.1
  end
  
  def teardown
    @world = nil
  end
  
  def test_strict_continuity
    testers = []
    ObjectSpace.each_object(Class) do |cl|
      if cl <= TestComponent and
         cl.instance_methods.include? "assert_consistent"
        testers << @world.create(cl)
      end
    end
    
    testers.each { |t| t.assert_consistent self }
    @world.run 10 do
      testers.each { |t| t.assert_consistent self }
    end
    testers.each { |t| t.finish self }
    
    a = testers.find {|t| t.class == A}
    assert(a)
    assert_equal(TestComponent::Exit, a.state)

    b = testers.find {|t| t.class == B}
    assert(b)
  end
  
  def test_algebraic_inconsistency1
    d = @world.create(D1)
    assert_raises(RedShift::StrictnessError) do
      @world.run 10
    end
  end
  
  def test_algebraic_inconsistency2
    d = @world.create(D2)
    assert_raises(RedShift::StrictnessError) do
      @world.run 10
    end
  end
end
