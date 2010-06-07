require 'redshift'

include RedShift

class Flow_Euler < Component
  flow do
    euler "x' = 1"
    euler "y_euler' = x" # y is a worse approx of z, due to Euler
    diff  "  y_rk4' = x"
    alg   "  y_true = 0.5 * pow(x,2)" # the true value
  end
end

world = World.new
c = world.create(Flow_Euler)


x, y_euler, y_rk4, y_true, rk4_err, euler_err = [], [], [], [], [], []
gather = proc do
  time = world.clock
  x << [time, c.x]
  y_euler << [time, c.y_euler]
  y_rk4 << [time, c.y_rk4]
  y_true << [time, c.y_true]
  rk4_err << [time, (c.y_rk4 - c.y_true).abs]
  euler_err << [time, (c.y_euler - c.y_true).abs]
end

gather.call
world.evolve 10 do
  gather.call
end

require 'redshift/util/plot'
include Plot::PlotUtils

gnuplot do |plot|
  plot.command %{set title "Euler Integration"}
  plot.command %{set xlabel "time"}
  plot.add x, %{title "x" with lines}
  plot.add y_true, %{title "y_true" with lp}
  plot.add y_rk4, %{title "y_rk4" with lp}
  plot.add y_euler, %{title "y_euler" with lp}
  plot.add rk4_err, %{title "rk4_err" with lp}
  plot.add euler_err, %{title "euler_err" with lp}
end
