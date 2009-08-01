# Measures performance of Euler integration.

require 'redshift'

include RedShift

module Euler
  class Flow_Euler < Component
    flow do
      euler "x' = 1"
      euler "y' = x" # Very bad!
    end
  end
  
  def self.make_world n=1
    w = World.new
    n.times do
      w.create(Flow_Euler)
    end
    w
  end

  def self.do_bench
    [ [       1, 1_000_000],
      [      10,   100_000],
      [     100,    10_000],
      [   1_000,     1_000],
      [  10_000,       100],
      [ 100_000,        10] ].each do
      |     n_c,     n_s|
      
      w = make_world(n_c)
      w.run 1 # warm up
      r = bench do
        w.run(n_s)
      end
      
      yield "  - %10d comps X %10d steps: %8.2f" % [n_c, n_s, r]
    end
  end
end

if __FILE__ == $0
  require 'bench'
  w = Euler.make_world(1000)
  time = bench do
    w.run(1000)
  end
  p time
end
