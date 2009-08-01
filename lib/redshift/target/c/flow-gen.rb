module RedShift

class Flow
  def translate flow_fn, result_var, rk_level, cl
    translation = {}
    setup = []    ## should use accumulator
    
    c_formula = @formula.dup
    strict = true
    
    re = /(?:([A-Za-z_]\w*)\.)?([A-Za-z_]\w*)(?!\w*\s*[(])/
    
    c_formula.gsub! re do |expr|

      unless translation[expr]
        link, var = $1, $2
        
        if link
          ## unless writer is private...
          strict = false # because link can change later in dstep
        
          # l.x  ==>  get_l__x()->value_n
          link_type = cl.link_type[link.intern]
          raise(NameError, "\nNo such link, #{link}") unless link_type
          flow_fn.include link_type.shadow_library_include_file
          
          link_cs_ssn = link_type.cont_state_class.shadow_struct.name

          link_cname = "link_#{link}"
          link_cs_cname = "link_cs_#{link}"
          checked_var_cname = "checked_#{link}__#{var}" ## not quite unambig.
          get_var_cname = "get_#{link}__#{var}"
          
          flow_fn.declare checked_var_cname => "int #{checked_var_cname}"
          flow_fn.setup   checked_var_cname => "#{checked_var_cname} = 0"
          
          unless translation[link + "."]
            translation[link + "."] = true # just so we know we've handled it
            
            unless translation[link]
              translation[link] = link_cname
              link_type_ssn = link_type.shadow_struct.name
              flow_fn.declare link_cname => "#{link_type_ssn} *#{link_cname}"
              flow_fn.setup   link_cname => "#{link_cname} = shadow->#{link}"
            end ## same as below
            
            flow_fn.declare link_cs_cname => "#{link_cs_ssn} *#{link_cs_cname}"
          end
          
          exc = flow_fn.declare_class(NilLinkError) ## class var
          msg = "Link #{link} is nil in component %s"
          insp = flow_fn.declare_symbol(:inspect) ## class var
          str = "STR2CSTR(rb_funcall(shadow->self, #{insp}, 0))"

          sh_cname = link_cname
          cs_cname = link_cs_cname
          flow_fn.declare get_var_cname => %{
            inline ContVar *#{get_var_cname}(void) {
              if (!#{checked_var_cname}) {
                #{checked_var_cname} = 1;
                if (!#{link_cname})
                  rb_raise(#{exc}, #{msg.inspect}, #{str});
                #{cs_cname} = (#{link_cs_ssn} *)#{link_cname}->cont_state;
                if (#{cs_cname}->#{var}.algebraic) {
                  if (#{cs_cname}->#{var}.rk_level < rk_level ||
                     (rk_level == 0 && #{cs_cname}->#{var}.d_tick != d_tick))
                    (*#{cs_cname}->#{var}.flow)((ComponentShadow *)#{sh_cname});
                }
              }
              return &(#{cs_cname}->#{var});
            }
          } ## algebraic test is same as below

          translation[expr] = "#{get_var_cname}()->value_#{rk_level}"
          
        else # expr == 'var'
          link_type = cl.link_type[var.intern]
          
          if link_type
            # l ==> link_l
            ## unless writer is private...
            strict = false # because link can change later in dstep

            link = var
            link_cname = "link_#{link}"
            unless translation[link]
              translation[link] = link_cname

              link_type_ssn = link_type.shadow_struct.name
              flow_fn.declare link_cname => "#{link_type_ssn} *#{link_cname}"
              flow_fn.setup   link_cname => "#{link_cname} = shadow->#{link}"
            end
            
          else ## if var on list of cont var
            # x ==> var_x
            var_obj = cl.cont_state_class.vars[var.intern]
            if not var_obj or var_obj.writable
              # note var must have been declared at this point
              # or else we can't use the strict optimization
              strict = false
            end
            
            var_cname = "var_#{var}"
            sh_cname = "shadow"
            cs_cname = "cont_state"
            translation[var] = var_cname

            flow_fn.declare var_cname => "double    #{var_cname}"
            flow_fn.setup var_cname => %{
              if (#{cs_cname}->#{var}.algebraic) {
                if (#{cs_cname}->#{var}.rk_level < rk_level ||
                   (rk_level == 0 && #{cs_cname}->#{var}.d_tick != d_tick))
                  (*#{cs_cname}->#{var}.flow)((ComponentShadow *)#{sh_cname});
              }
            }
            setup << %{
              #{var_cname} = #{cs_cname}->#{var}.value_#{rk_level};
            }.tabto(0).split("\n")
          
          ## elsif... else error
          end
          
        end
      end
      translation[expr]
    end
    
    yield strict if block_given?  ## funky way to return another value
    
    setup << "#{result_var} = #{c_formula}"
  end
    
end


class AlgebraicFlow
  def flow_wrapper cl, state
    var_name = @var
    flow = self
    flow_name = "flow_#{CGenerator.make_c_name cl.name}_#{var_name}_#{state}"
    
    Component::FlowWrapper.make_subclass flow_name do
      ssn = cl.shadow_struct.name
      cont_state_ssn = cl.cont_state_class.shadow_struct.name
      
      # We need the struct
      shadow_library_source_file.include(cl.shadow_library_include_file)
      
      shadow_library_source_file.define(flow_name).instance_eval do
        arguments "ComponentShadow *comp_shdw"
        declare :shadow => %{
          struct #{ssn} *shadow;
          struct #{cont_state_ssn} *cont_state;
          ContVar  *var;
        }
        setup :shadow => %{
          shadow = (#{ssn} *)comp_shdw;
          cont_state = (#{cont_state_ssn} *)shadow->cont_state;
          var = &cont_state->#{var_name};
          assert(var->algebraic);
          if (var->nested) {
            rb_gv_set("$rs", shadow->self);
            rb_raise(#{declare_class CircularDefinitionError},
              "\\nCircularity in algebraic formula for #{var_name} in state #{state} of class #{cl.name}. The component is in $rs.");
          }
          var->nested = 1;
        }
        ## optimization: it might be possible to translate once and
        ## use gsub to make each of the four versions, or use a template.
        body %{
          
          switch (rk_level) {
          case 0:
            #{flow.translate(self, "var->value_0", 0, cl).join("
            ")};
            var->d_tick = d_tick;
            break;
          case 1:
            #{flow.translate(self, "var->value_1", 1, cl).join("
            ")};
            var->rk_level = rk_level;
            break;
          case 2:
            #{flow.translate(self, "var->value_2", 2, cl).join("
            ")};
            var->rk_level = rk_level;
            break;
          case 3:
            #{flow.translate(self, "var->value_3", 3, cl){|strict|
              flow.instance_eval {@strict = strict}
            }.join("
            ")};
            var->rk_level = rk_level;
            break;
          default:
            rb_raise(#{declare_class RuntimeError},
              "Bad rk_level, %d!", rk_level);
          }
          
          var->nested = 0;
        }
      end # Case 0 applies during discrete update.
          # alg flows are lazy

      define_c_method :calc_function_pointer do
        body "shadow->flow = &#{flow_name}", "shadow->algebraic = 1"
      end
    end
  end

end # class AlgebraicFlow


class EulerDifferentialFlow

  def flow_wrapper cl, state
    var_name = @var
    flow = self
    
    flow_name = "flow_#{CGenerator.make_c_name cl.name}_#{var_name}_#{state}"
    
    Component::FlowWrapper.make_subclass flow_name do
      ssn = cl.shadow_struct.name
      cont_state_ssn = cl.cont_state_class.shadow_struct.name
      
      # We need the struct
      shadow_library_source_file.include(cl.shadow_library_include_file)
      
      shadow_library_source_file.define(flow_name).instance_eval do
        arguments "ComponentShadow *comp_shdw"
        declare :shadow => %{
          struct #{ssn} *shadow;
          struct #{cont_state_ssn} *cont_state;
          ContVar  *var;
          double    ddt_#{var_name};
        }
        setup :shadow => %{
          if (rk_level == 2) {
            shadow = (#{ssn} *)comp_shdw;
            cont_state = (#{cont_state_ssn} *)shadow->cont_state;
            var = &cont_state->#{var_name};
          }
        }
        setup :rk_level => %{
          rk_level -= 2;
        } # has to happen before referenced alg flows are called in other setups
        body %{
          if (rk_level == 0) {
            #{flow.translate(self, "ddt_#{var_name}", 0, cl).join("
            ")};

            var->value_0 = var->value_3 = var->value_2 =
              var->value_0 + time_step * ddt_#{var_name};
            
            var->rk_level = 4;
          }
          rk_level += 2;
        }
      end ## setting var->rk_level=4 saves two function calls
          ## but there's still the wasted rk_level=1 function call...
          ## this might be a reason to handle euler steps at rk_level=1
      define_c_method :calc_function_pointer do
        body "shadow->flow = &#{flow_name}"
      end
    end
  end

end # class EulerDifferentialFlow


class RK4DifferentialFlow
  
  def flow_wrapper cl, state
    var_name = @var
    flow = self
    
    flow_name = "flow_#{CGenerator.make_c_name cl.name}_#{var_name}_#{state}"
    
    Component::FlowWrapper.make_subclass flow_name do
      ssn = cl.shadow_struct.name
      cont_state_ssn = cl.cont_state_class.shadow_struct.name
      
      # We need the struct
      shadow_library_source_file.include(cl.shadow_library_include_file)
      
      shadow_library_source_file.define(flow_name).instance_eval do
        arguments "ComponentShadow *comp_shdw"
        declare :shadow => %{
          struct #{ssn} *shadow;
          struct #{cont_state_ssn} *cont_state;
          ContVar  *var;
          double    ddt_#{var_name};
          double    value_4;
        }
        setup :shadow => %{
          shadow = (#{ssn} *)comp_shdw;
          cont_state = (#{cont_state_ssn} *)shadow->cont_state;
          var = &cont_state->#{var_name};
        }
        setup :rk_level => %{
          rk_level--;
        } # has to happen before referenced alg flows are called in other setups
        body %{
          switch (rk_level) {
          case 0:
            #{flow.translate(self, "ddt_#{var_name}", 0, cl).join("
            ")};
            var->value_1 = var->value_0 + ddt_#{var_name} * time_step/2;
            break;

          case 1:
            #{flow.translate(self, "ddt_#{var_name}", 1, cl).join("
            ")};
            var->value_2 = var->value_0 + ddt_#{var_name} * time_step/2;
            break;

          case 2:
            #{flow.translate(self, "ddt_#{var_name}", 2, cl).join("
            ")};
            var->value_3 = var->value_0 + ddt_#{var_name} * time_step;
            break;

          case 3:
            #{flow.translate(self, "ddt_#{var_name}", 3, cl).join("
            ")};
            value_4 = var->value_0 + ddt_#{var_name} * time_step;
            var->value_0 = 
              (-3*var->value_0 + 2*var->value_1 + 4*var->value_2 +
                2*var->value_3 + value_4) / 6;
            break;

          default:
            rb_raise(#{declare_class RuntimeError},
              "Bad rk_level, %d!", rk_level);
          }
          
          rk_level++;
          var->rk_level = rk_level;
        }
      end

      define_c_method :calc_function_pointer do
        body "shadow->flow = &#{flow_name}"
      end
    end
  end

end # class RK4DifferentialFlow


class CexprGuard < Flow ## Kinda funny...

  def initialize f
    super nil, f
  end
  
  @@serial = 0
  
  # +cl+ is the component class
  ## maybe all these methods should just be called wrapper?
  def guard_wrapper cl
    guard = self
    cl_cname = CGenerator.make_c_name cl.name
    g_cname = "Guard_#{@@serial}"; @@serial += 1
    guard_name = "guard_#{cl_cname}_#{g_cname}"
    
    Component::GuardWrapper.make_subclass guard_name do
      ssn = cl.shadow_struct.name
      cont_state_ssn = cl.cont_state_class.shadow_struct.name
      
      # We need the struct
      shadow_library_source_file.include(cl.shadow_library_include_file)
      
      strict = false
      
      ## should use some other file (likewise for Flows)
      shadow_library_source_file.define(guard_name).instance_eval do
        arguments "ComponentShadow *comp_shdw"
        return_type "int"
        declare :shadow => %{
          struct #{ssn} *shadow;
          struct #{cont_state_ssn} *cont_state;
          ContVar  *var;
        }
        setup :shadow => %{
          shadow = (#{ssn} *)comp_shdw;
          cont_state = (#{cont_state_ssn} *)shadow->cont_state;
        }
        declare :result => "int result"
        translation = guard.translate(self, "result", 0, cl) {|s| strict = s}
        body %{
          #{translation.join("
          ")};
          return result;
        }
      end
      
      @strict = strict
      
      define_c_method :calc_function_pointer do
        body "shadow->guard = &#{guard_name}"
      end
    end
  end

end

class Expr < Flow ## Kinda funny...
  def initialize f
    super nil, f
  end
  
  @@serial = 0
  
  # +cl+ is the component class
  def wrapper(cl)
    expr = self
    cl_cname = CGenerator.make_c_name cl.name
    ex_cname = "Expr_#{@@serial}"; @@serial += 1
    expr_name = "expr_#{cl_cname}_#{ex_cname}"
    
    Component::ExprWrapper.make_subclass expr_name do
      ssn = cl.shadow_struct.name
      cont_state_ssn = cl.cont_state_class.shadow_struct.name
      
      # We need the struct
      shadow_library_source_file.include(cl.shadow_library_include_file)
      
      ## should use some other file (likewise for Flows)
      shadow_library_source_file.define(expr_name).instance_eval do
        arguments "ComponentShadow *comp_shdw"
        return_type "double"
        declare :shadow => %{
          struct #{ssn} *shadow;
          struct #{cont_state_ssn} *cont_state;
          ContVar  *var;
        }
        setup :shadow => %{
          shadow = (#{ssn} *)comp_shdw;
          cont_state = (#{cont_state_ssn} *)shadow->cont_state;
        }
        declare :result => "double result"
        translation = expr.translate(self, "result", 0, cl)
        body %{
          #{translation.join("
          ")};
          return result;
        }
      end
      
      define_c_method :calc_function_pointer do
        body "shadow->expr = &#{expr_name}"
      end
    end
  end
end

end # module RedShift
