module RedShift

  class Component
    include CShadow
    shadow_library RedShift.library
    shadow_library_file "Component"
    library = RedShift.library
    
    subclasses.each do |sub|
      file_name = CGenerator.make_c_name(sub.name).to_s
      sub.shadow_library_file file_name
    end
    
    ## it would be better to allow subclassing post-commit, but only if
    ## non-compiled stuff is overridden in subclass
    after_commit {subclasses.freeze}

    library.declare_extern :typedefs => %{
      typedef struct #{shadow_struct_name} ComponentShadow;
      typedef void (*Flow)(ComponentShadow *);  // evaluates one variable
      typedef int (*Guard)(ComponentShadow *);  // evaluates a guard expr
      typedef double (*Expr)(ComponentShadow *);// evaluates a numerical expr
      typedef struct {
        unsigned    d_tick    : 16; // last discrete tick at which flow computed
        unsigned    rk_level  :  3; // last rk level at which flow was computed
        unsigned    algebraic :  1; // should compute flow when inputs change?
        unsigned    nested    :  1; // to catch circular evaluation
        Flow        flow;           // cached flow function of current state
        double      value_0;        // value during discrete step
        double      value_1;        // value at steps of Runge-Kutta
        double      value_2;
        double      value_3;
      } ContVar;
    }.tabto(0)

    class FlowAttribute < CNativeAttribute
      @pattern = /\A(Flow)\s+(\w+)\z/
    end

    class GuardAttribute < CNativeAttribute
      @pattern = /\A(Guard)\s+(\w+)\z/
    end

    class ExprAttribute < CNativeAttribute
      @pattern = /\A(Expr)\s+(\w+)\z/
    end

    class ContVarAttribute < CNativeAttribute
      @pattern = /\A(ContVar)\s+(\w+)\z/

      def initialize(*args)
        super
        # value_0 is the relevant state outside of continuous update
        @dump = "rb_ary_push(result, rb_float_new(shadow->#{@cvar}.value_0))"
        @load = "shadow->#{@cvar}.value_0 = NUM2DBL(rb_ary_shift(from_array))"
      end
    end

    # Useful way to represent an object that has compile time (pre-commit) and
    # run-time (post-commit) bevahior. The compile time behavior is in the
    # class, and the run time behavior is in the unique instance.
    class SingletonShadowClass
      include Singleton
      include CShadow; shadow_library Component
      persistent false
      def inspect; self.class.inspect_str; end
      class << self; attr_reader :inspect_str; end
    end

    # FunctionWrappers wrap function pointers for access from ruby.
    class FunctionWrapper < SingletonShadowClass
      def initialize
        calc_function_pointer
      end
      def self.make_subclass(file_name, &bl)
        cl = Class.new(self)
        cl.shadow_library_file file_name
        clname = file_name.sub /^#{@tag}/i, @tag
        Object.const_set clname, cl
        before_commit {cl.class_eval &bl}
          # this is deferred to commit time to resolve forward refs
          ## this would be more elegant with defer.rb
          ## maybe precommit should be used for this now?
        cl
      end
    end

    class FlowWrapper < FunctionWrapper
      shadow_attr :flow => "Flow flow"
      shadow_attr :algebraic => "int algebraic"
      @tag = "Flow"
    end

    class GuardWrapper < FunctionWrapper
      shadow_attr :guard => "Guard guard"
      @tag = "Guard"

      def self.strict; @strict; end
      def strict; @strict ||= self.class.strict; end
    end
    
    class ExprWrapper < FunctionWrapper
      shadow_attr :expr => "Expr expr"
      @tag = "Expr"
    end
    
    # one per variable, shared by subclasses which inherit it
    # not a run-time object, except for introspection
    class ContVarDescriptor
      attr_reader :name, :kind
      def initialize name, index_delta, cont_state, kind
        @name = name
        @index_delta = index_delta
        @cont_state = cont_state
        @kind = kind
      end
      def strict?; @kind == :strict; end
      def index
        @cont_state.inherited_var_count + @index_delta
      end
    end

    # One subclass per component subclass; one instance per component.
    # Must have only ContVars in the shadow struct.
    class ContState
      include CShadow; shadow_library Component

      ## maybe this should be in cgen as "shadow_aligned N"
      unless /mswin/i =~ RUBY_PLATFORM
        shadow_struct.declare :begin_vars =>
          "struct {} begin_vars __attribute__ ((aligned (8)))"
          # could conceivably have to be >8, or simply ((aligned)) on some
          # platforms but this seems to work for x86 and sparc
      end
      
      class_superhash :vars
      
      def vars
        self.class.vars
      end
      
      def var_at_index(idx)
        self.class.var_at_index(idx)
      end

      class << self
        def make_subclass_for component_class
          if component_class == Component
            cl = ContState
          else
            sup = component_class.superclass.cont_state_class
            cl = component_class.const_set("ContState", Class.new(sup))
          end
          cl.instance_eval do
            @component_class = component_class
            file_name =
              component_class.shadow_library_source_file.name[/.*(?=\.c$)/] +
              "_ContState"     ## a bit hacky
            shadow_library_file file_name
            component_class.shadow_library_include_file.include(
              shadow_library_include_file)
          end
          cl
        end

        # yields to block only if var was added
        def add_var var_name, kind
          var = vars[var_name]
          if var
            unless kind == :permissive or var.kind == kind
              raise StrictnessError,
                "\nVariable #{var_name} redefined with different strictness."
            end
          else
            var = vars[var_name] =
              ContVarDescriptor.new(var_name, vars.own.size, self, kind)
            shadow_attr var_name => "ContVar #{var_name}"
            yield if block_given?
          end
          var
        end

        def inherited_var_count
          unless @inherited_var_count
            raise Library::CommitError unless committed?
            @inherited_var_count = superclass.vars.size
          end
          @inherited_var_count
        end
        
        def cumulative_var_count
          unless @cumulative_var_count
            raise Library::CommitError unless committed?
            @cumulative_var_count = vars.size
          end
          @cumulative_var_count
        end
        
        def var_at_index(idx)
          @var_at_index ||= {}
          @var_at_index[idx] ||= vars.values.find {|var| var.index == idx}
        end
      end
    end

    _load_data_method.post_code %{
      rb_funcall(shadow->self, #{library.declare_symbol :restore}, 0);
    }

    shadow_attr_accessor :cont_state   => [ContState]
    protected :cont_state, :cont_state=

    shadow_attr_accessor :state        => State
    protected :state=

    shadow_attr_accessor :var_count    => "long var_count"
      ## needn't be persistent
    protected :var_count=

    shadow_attr_reader :nonpersistent, :outgoing    => Array
    shadow_attr_reader :nonpersistent, :trans       => Transition
    shadow_attr_reader :nonpersistent, :phases      => Array
    shadow_attr_reader :nonpersistent, :dest        => State

    # The values of each event currently being emitted, indexed by event ID.
    # If not emitted, nil. We consider false to be an emitted value.
    shadow_attr_accessor :nonpersistent, :event_values      => Array
    shadow_attr_accessor :nonpersistent, :next_event_values => Array
    protected :event_values=, :next_event_values=

    def active_transition; trans; end # for introspection

    ## these should be short, or bitfield
    shadow_attr :nonpersistent, :cur_ph => "long cur_ph" # index of upcoming ph
    shadow_attr :nonpersistent, :strict => "long strict" # is cur state strict?

    class << self

      # The flow hash contains flows contributed (not inherited) by this
      # class. The flow table is the cumulative hash (by state) of arrays
      # (by var) of flows.

      def flow_hash
        @flow_hash ||= {}
      end

      def add_flow h      # [state, var] => flow_wrapper_subclass, ...
        flow_hash.update h
      end

      def flow_table
        unless @flow_table
          assert committed?
          ft = {}
          if defined? superclass.flow_table
            for k, v in superclass.flow_table
              ft[k] = v.dup
            end
          end
          for (state, var), flow_class in flow_hash
            (ft[state] ||= [])[var.index] = flow_class.instance
          end
          @flow_table = ft
        end
        @flow_table
      end

      def var_count
        @var_count ||= cont_state_class.cumulative_var_count
      end

      def cont_state_class
        @cont_state_class ||= ContState.make_subclass_for(self)
      end
      
      def define_continuous(kind, var_names)
        var_names.collect do |var_name|
          var_name = var_name.intern if var_name.is_a? String
          
          cont_state_class.add_var var_name, kind do
            ssn = cont_state_class.shadow_struct.name
            exc = shadow_library.declare_class(AlgebraicAssignmentError)
            msg = "\\\\nCannot set #{var_name}; it is defined algebraically."

            class_eval %{
              define_c_method :#{var_name} do
                declare :cont_state => "#{ssn} *cont_state"
                body %{
                  cont_state = (#{ssn} *)shadow->cont_state;
                  if (cont_state->#{var_name}.algebraic &&
                      cont_state->#{var_name}.d_tick != d_tick)
                    (*cont_state->#{var_name}.flow)((ComponentShadow *)shadow);
                }
                returns "rb_float_new(cont_state->#{var_name}.value_0)"
              end
            }

            if kind == :strict
              exc2 = shadow_library.declare_class ContinuousAssignmentError
              msg2 = "Cannot reset strictly continuous #{var_name} in #{self}."
              class_eval %{
                define_c_method :#{var_name}= do
                  arguments :value
                  declare :cont_state => "#{ssn} *cont_state"
                  body %{
                    cont_state = (#{ssn} *)shadow->cont_state;
                    if (cont_state->#{var_name}.algebraic)
                      rb_raise(#{exc}, #{msg.inspect});
                    if (!NIL_P(shadow->state))
                      rb_raise(#{exc2}, #{msg2.inspect});
                    cont_state->#{var_name}.value_0 = NUM2DBL(value);
                    d_tick++;
                  }
                  returns "value"
                end
              }

            else
              class_eval %{
                define_c_method :#{var_name}= do
                  arguments :value
                  declare :cont_state => "#{ssn} *cont_state"
                  body %{
                    cont_state = (#{ssn} *)shadow->cont_state;
                    if (cont_state->#{var_name}.algebraic)
                      rb_raise(#{exc}, #{msg.inspect});
                    cont_state->#{var_name}.value_0 = NUM2DBL(value);
                    d_tick++;
                  }
                  returns "value"
                end
              }
            end
          end
        end
      end

      def define_constant(kind, var_names)
        var_names.collect do |var_name|
          var_name = var_name.intern if var_name.is_a? String
          
          if kind == :strict
            shadow_attr_reader var_name => "double #{var_name}"
            exc2 = shadow_library.declare_class ContinuousAssignmentError
            msg2 = "Cannot reset strictly continuous #{var_name} in #{self}."
            
            class_eval %{
              define_c_method :#{var_name}= do
                arguments :value
                body %{
                  if (!NIL_P(shadow->state))
                    rb_raise(#{exc2}, #{msg2.inspect});
                  shadow->#{var_name} = NUM2DBL(value);
                  d_tick++;
                }
                returns "value"
              end
            }
            
          else
            shadow_attr_accessor var_name => "double #{var_name}"
          end
        end
      end

      def precommit
        define_events
        define_links
        define_continuous_variables
        define_constant_variables

        states.values.sort_by{|s|s.to_s}.each do |state|
          define_flows(state)
          define_transitions(state)
        end
      end
    
      def define_events
        exported_events.own.each do |event, index|
          define_method event do
            event_values.at(index) ## is it worth doing this in C?
          end                      ## or at least use eval instead of closure
        end
      end
    
      def calc_link_offset(link_sym)
        raise "#{link_sym} is not a valid link in #{self.class}"
      end

      def define_links
        own_links = link_type.own
        return if own_links.empty?
        
        calc_link_offset_method = define_c_class_method :calc_link_offset do
          arguments :link_sym
          declare :offset => "int offset"
          returns %{rb_call_super(1, &link_sym)}
          # or we could embed superclass.calc_link_offset_method.body!
        end

        ssn = shadow_struct.name
        
        own_links.keys.sort_by{|k|k.to_s}.each do |var_name|
          var_type = link_type[var_name]

          unless var_type.is_a? Class
            var_type = var_type.to_s.split(/::/).inject(Object) do |p, n|
              p.const_get(n)
            end
            link_type[var_name] = var_type
          end

          unless var_type < Component
            raise TypeError,
            "Linked type must be a subclass of Component: #{var_name}"
          end

          shadow_attr_accessor var_name => [var_type]
          shadow_library_include_file.include(
            var_type.shadow_library_include_file)
          
          calc_link_offset_method.body %{
            if (link_sym == #{shadow_library.literal_symbol(var_name)}) {
              offset = (char *)&(((struct #{ssn} *)0)->#{var_name}) - (char *)0;
              return INT2FIX(offset);
            }
          }
        end
      end
      ### shadow_attr won't accept redefinition, and anyway there is
      ###   the contra/co variance problem.
      
      def define_continuous_variables
        continuous_variables.own.keys.sort_by{|k|k.to_s}.each do |var_name|
          define_continuous(continuous_variables[var_name], [var_name])
        end
      end
      
      def define_constant_variables
        constant_variables.own.keys.sort_by{|k|k.to_s}.each do |var_name|
          define_constant(constant_variables[var_name], [var_name])
        end
      end
      
      def define_flows(state)
        own_flows = flows(state).own
        own_flows.keys.sort_by{|sym|sym.to_s}.each do |var|
          flow = own_flows[var]

          cont_var = cont_state_class.vars[var]
          unless cont_var
            attach_continuous_variables(:permissive, [var])
            cont_var = define_continuous(:permissive, [var])[0]
          end
          
          add_flow([state, cont_var] => flow.flow_wrapper(self, state))

          after_commit do
            ## a pity to use after_commit, when "just_before_commit" would be ok
            ## use the defer mechanism from teja2hsif
            if not flow.strict and cont_var.strict?
              raise StrictnessError,
                "Variable #{cont_var.name} redefined with different strictness."
            end
          end
        end
      end

      def define_guard(expr)
        CexprGuard.new(expr).guard_wrapper(self)
      end

      def define_guards(guards)
        guards.map! do |g|
          case g
          when GuardPhaseItem, Proc
            # already saw this guard, as in: transition [S, T] => U
            g
          
          when Class
            if g < GuardWrapper
              g
            else
              raise "What is #{g.inspect}?"
            end

          when String
            define_guard(g)
          
          when Array
            var_name, event_name = g

            var_type = link_type[var_name]
            event_idx = var_type.exported_events[event_name]
            
            unless event_idx
              raise "Can't find event #{event_name.inspect} in events of" +
                    " #{var_type}, linked from #{self} as #{var_name.inspect}."
            end

            item = GuardPhaseItem.new
            item.event_index = event_idx
            item.link = var_name
            item.event = event_name

            after_commit do
              item.link_offset = calc_link_offset(var_name)
            end

            item

          else
            raise "What is #{g.inspect}?"
          end
        end
      end
      
      def define_reset(expr)
        ## optimization: if the same fmla is used in two places with the
        ## same context, use the same wrapper
        Expr.new(expr).wrapper(self)
      end
      
      def define_resets(phase)
        h = phase.value_map
        h.keys.sort_by{|k|k.to_s}.each do |var|
          expr = h[var]
          cont_var = cont_state_class.vars[var]
          ### what about reseting link vars?
          unless cont_var
            raise "No such variable, #{var}"
          end
          
          if cont_var.strict?
            raise ContinuousAssignmentError,
              "Cannot reset strictly continuous #{var} in #{self}.", []
          end
          
          case expr
          when String
            reset = define_reset(expr)

            after_commit do
              phase[cont_var.index] = reset.instance
            end

          else
            after_commit do
              phase[cont_var.index] = expr
            end
          end
        end
      end
      
      def define_transitions(state)
        own_trans = transitions(state).own

        own_trans.keys.sort_by{|k|k.to_s}.each do |name|
          trans, dest = own_trans[name]

          guards = trans.guard
          define_guards(guards) if guards
          
          trans.phases.each do |phase|
            case phase
            when ResetPhase
              define_resets(phase)
            end
          end
        end
      end

    end

    define_c_method :update_cache do body "__update_cache(shadow)" end

    library.define(:__update_cache).instance_eval do
      flow_wrapper_type = RedShift::Component::FlowWrapper.shadow_struct.name
      scope :extern ## might be better to keep static and put in world.c
      arguments "struct #{RedShift::Component.shadow_struct.name} *shadow"
      declare :locals => %{
        #{flow_wrapper_type} *flow_wrapper;

        VALUE       flow_table;       //# Hash
        VALUE       flow_array;       //# Array
        VALUE       outgoing;
        long        var_count;
        ContVar    *vars;
        long        i;
        long        count;
        VALUE      *flows;
        VALUE       strict;
      }.tabto(0)

      body %{
        //# Cache outgoing transitions as [t, g, [phase0, phase1, ...], dest, ...]
        shadow->outgoing = rb_funcall(shadow->self,
                           #{declare_symbol :outgoing_transitions}, 0);

        strict = rb_funcall(shadow->outgoing, #{declare_symbol :pop}, 0);
        shadow->strict = RTEST(strict);

        //# Cache flows.
        var_count = shadow->var_count;
        vars = (ContVar *)(&shadow->cont_state->begin_vars);

        for (i = 0; i < var_count; i++) {
          vars[i].flow = 0;
          vars[i].algebraic = 0;
          vars[i].d_tick = 0;
        }

        flow_table = rb_funcall(rb_obj_class(shadow->self),
                     #{declare_symbol :flow_table}, 0);
          //## could use after_commit to cache this method call
        flow_array = rb_hash_aref(flow_table, shadow->state);

        if (flow_array != Qnil) {
          Check_Type(flow_array, T_ARRAY); //## debug only

          count = RARRAY(flow_array)->len;
          flows = RARRAY(flow_array)->ptr;

          if (count > var_count)
            rb_raise(#{declare_class IndexError},
                   "Index into continuous variable list out of range: %d > %d.",
                   count, var_count);

          for (i = 0; i < count; i++)
            if (flows[i] != Qnil) {
              Data_Get_Struct(flows[i], #{flow_wrapper_type}, flow_wrapper);
              vars[i].flow      = flow_wrapper->flow;
              vars[i].algebraic = flow_wrapper->algebraic;
            }
        }
      }
    end

    shadow_attr_reader :world => World

    define_c_method :__set__world do
      arguments :world
      body "shadow->world = world"
    end
    protected :__set__world

  #if false
  #  define_c_method :recalc_alg_flows do ### need this?
  #    declare :locals => %{
  #      ContVar    *vars;
  #      long        i;
  #      long        var_count;
  #    }.tabto(0)
  #    
  #    body %{
  #      var_count = shadow->type_data->var_count;
  #      vars = (ContVar *)(&shadow->cont_state->begin_vars);
  #      for (i = 0; i < var_count; i++)
  #        if (vars[i].algebraic)
  ## also check d_tick
  #          (*vars[i].flow)((ComponentShadow *)shadow);
  #    }
  #  end
  #
  #  define_c_method :increment_d_tick do
  #    body "d_tick++"
  #  end
  #end

  end

end
