require 'pstore'
require 'enum/op'

module RedShift

class ZenoError < RuntimeError; end

# Set zeno_level to this to turn off zeno checking.
ZENO_UNLIMITED = -1

class World
  include Enumerable

  {
    :Debugger       => "debugger",
    :ZenoDebugger   => "zeno-debugger"
  }.each {|m,f| autoload(m, "redshift/mixins/#{f}")}

  class ComponentList < EnumerableOperator::Sum
    def inspect
      to_a.inspect # looks better in irb
    end
    
    def [](idx)
      to_a[idx] ## very inefficient
    end
    
    def clear
      summands.each {|list| list.clear}
    end
  end

  @subclasses = []

  class << self
    # World is not included in subclasses. This returns nil when called on subs.
    attr_reader :subclasses

    def inherited(sub)
      World.subclasses << sub
    end
  end
  
  # see comment in redshift.rb
  def self.new(*args, &block)
    RedShift.require_target     # redefines World.new
    new(*args, &block)          # which is what this line calls
  end
  
  attr_reader :components
  
  def default_options
    {
      :name         =>  "#{self.class}_#{@@count}",
      :time_unit    =>  "second",
      :time_step    =>  0.1,
      :zeno_limit   =>  100,
      :clock_start  =>  0.0,
      :clock_finish =>  Infinity,
    }
  end

  @@count = 0

  attr_accessor :name, :time_unit
  
  def started?; @started; end
  def running?; @running; end

  # Can override the options using assignments in the block.
  def initialize # :yields: world
    self.curr_A = []; self.curr_CR = []; self.curr_T = []
    self.active_E = []; self.prev_active_E = []
    self.awake = []; self.prev_awake = []
    self.strict_sleep = []; self.inert = []
    self.diff_list = []
    @components = ComponentList.new  \
      awake, prev_awake, curr_T, strict_sleep, inert # _not_ diff_list

    options = default_options

    @name             = options[:name]
    @time_unit        = options[:time_unit]
    self.time_step    = options[:time_step]
    self.zeno_limit   = options[:zeno_limit]
    self.clock_start  = options[:clock_start]
    self.clock_finish = options[:clock_finish]
    
    self.step_count = 0
    
    @@count += 1

    do_defaults
    yield self if block_given?
  end
  
  def do_defaults
    self.class.do_defaults self
  end
  private :do_defaults
  
  def self.do_defaults instance
    superclass.do_defaults instance if superclass.respond_to? :do_defaults
    if @defaults_procs
      @defaults_procs.each do |pr|
        instance.instance_eval(&pr)
      end
    end
  end
  
  def do_setup
    self.class.do_setup self
    if @setup_procs
      @setup_procs.each do |pr|
        instance_eval(&pr)
      end
      @setup_procs = nil # so we can serialize
    end
  end
  private :do_setup
  
  def self.do_setup instance
    superclass.do_setup instance if superclass.respond_to? :do_setup
    if @setup_procs
      @setup_procs.each do |pr|
        instance.instance_eval(&pr)
      end
    end
  end

  def create(component_class)
    component = 
      if block_given?
        component_class.new(self) {|c| yield c}
      else
        component_class.new(self)
      end
    
    unless component.is_a? Component # Component is abstract
      raise TypeError, "#{component.class} is not a Component class"
    end
    
    awake << component
    component
  end
  
  ## is this a good idea? tests? #add ?
  def remove c
    if components.summands.any? {|list| list.delete(c)}
      raise unless c.world == self
      c.__set_world(nil)
    else
      raise "Tried to remove #{c} from #{self}, but its world is #{c.world}."
    end
  end
  
  # All evolution methods untimately call step, which can be overridden.
  # After each step, yields to block. It is the block's responsibility to
  # step_discrete at this point after changing any vars.
  def step(steps = 1)
    @running = true
    
    unless @started
      do_setup
      @started = true
    end
    
    step_discrete
    steps.to_i.times do
      break if clock > clock_finish
      self.step_count += 1
      step_continuous
      step_discrete
      @running = false
      yield self if block_given?
      @running = true
    end
    
    self
    
  ensure
    @running = false
    ## how to continue stepping after an exception?
  end
  
  def run(*args, &block)
    ## warn "World#run is deprecated -- use #step or #evolve"
    step(*args, &block)
  end
  
  def evolve(time = 1.0, &block)
    run((time.to_f/time_step).round, &block)
  end

  # Default implementation is to raise RedShift::ZenoError.
  def step_zeno
    raise RedShift::ZenoError, "Exceeded zeno limit of #{zeno_limit}."
  end
  
  ## is this a good idea? tests?
  def garbage_collect
    self.components.clear
    GC.start
    ObjectSpace.each_object(Component) do |c|
      components << c if c.world == self
    end
  end
  
  def each(&b)
    @components.each(&b)
  end
  
  def size
    @components.size
  end
  
  def include? component
    component.world == self
  end
  alias member? include?
  
  def inspect
    if @started
      digits = -Math.log10(time_step).floor
      digits = 0 if digits < 0

      data = []
      data << "%d step%s" % [step_count, ("s" if step_count != 1)]
      data << "%.#{digits}f #{@time_unit}%s" % [clock, ("s" if clock != 1)]
      data << "%d component%s" % [size, ("s" if size != 1)]
      data << "discrete step = #{discrete_step}" ## only if in step_discrete?
    else
      data = ["not started. Do 'run 0' to setup, or 'run n' to run."]
    end

    str = [name, data.join("; ")].join(": ")
    "<#{str}>"
  end
  
  def save filename = @name
    raise "Can't save world during its run method." if @running
    File.delete(filename) rescue SystemCallError
    store = PStore.new filename
    store.transaction do
      store['world'] = self
      yield store if block_given?
    end
  end
  
  def World.open filename
    world = nil
    store = PStore.new filename
    store.transaction do
      if store.root? 'world'
        world = store['world']
        yield store if block_given?
      end
    end
    world
  end
  
end # class World

end # module RedShift
