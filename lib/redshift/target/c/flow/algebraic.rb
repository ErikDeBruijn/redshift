module RedShift; class AlgebraicFlow
  def flow_wrapper cl, state
    var_name = @var
    flow = self
    flow_name = "flow_#{CGenerator.make_c_name cl.name}_#{var_name}_#{state}"
    
    Component::FlowWrapper.make_subclass flow_name do
      @inspect_str = "#{cl.name}:#{state}: #{var_name} = #{flow.formula}"

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
        exc = declare_class CircularDefinitionError
        msg = "Circularity in algebraic formula for #{var_name} in state " +
              "#{state} of class #{cl.name}."
        ## note that state may not be the same as the object's state, due
        ## to flow wrapper caching
        
        setup :shadow => %{
          shadow = (#{ssn} *)comp_shdw;
          cont_state = (#{cont_state_ssn} *)shadow->cont_state;
          var = &cont_state->#{var_name};
          assert(var->algebraic);
          if (shadow->world->alg_nest > 100) {
            shadow->world->alg_nest = 0;
            rs_raise(#{exc}, shadow->self, #{msg.inspect});
          }
          shadow->world->alg_nest++;
        }
        ## 100 not always enough, so could increase limit exponentially,
        ## and look in subsequent iterations for repeats of this [var, obj].
        
        ## optimization: it might be possible to translate once and
        ## use gsub to make each of the four versions, or use a template.
        body %{
          switch (shadow->world->rk_level) {
          case 0:
            #{flow.translate(self, "var->value_0", 0, cl).join("
            ")};
            var->d_tick = shadow->world->d_tick;
            break;
            
          case 1:
            #{flow.translate(self, "var->value_1", 1, cl).join("
            ")};
            var->rk_level = shadow->world->rk_level;
            break;
            
          case 2:
            #{flow.translate(self, "var->value_2", 2, cl).join("
            ")};
            var->rk_level = shadow->world->rk_level;
            break;
            
          case 3:
            #{flow.translate(self, "var->value_3", 3, cl){|strict|
              flow.instance_eval {@strict = strict}
            }.join("
            ")};
            var->rk_level = shadow->world->rk_level;
            break;
            
          default:
            rb_raise(#{declare_class RuntimeError},
              "Bad rk_level, %d!", shadow->world->rk_level);
          }
          
          shadow->world->alg_nest--;
        }
      end # Case 0 applies during discrete update.
          # alg flows are lazy

      define_c_method :calc_function_pointer do
        body "shadow->flow = &#{flow_name}", "shadow->algebraic = 1"
      end
    end
  end
end; end
