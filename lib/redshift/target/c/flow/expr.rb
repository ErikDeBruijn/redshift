class RedShift::CexprGuard

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
      @inspect_str = guard.formula.inspect

      ssn = cl.shadow_struct.name
      cont_state_ssn = cl.cont_state_class.shadow_struct.name
      
      # We need the struct
      shadow_library_source_file.include(cl.shadow_library_include_file)
      
      strict = false
      
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
      ## should set guard.strict = strict too?
      
      define_c_method :calc_function_pointer do
        body "shadow->guard = &#{guard_name}"
      end
    end
  end
end

class RedShift::Expr
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
      @inspect_str = expr.formula.inspect

      ssn = cl.shadow_struct.name
      cont_state_ssn = cl.cont_state_class.shadow_struct.name
      
      # We need the struct
      shadow_library_source_file.include(cl.shadow_library_include_file)
      
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
