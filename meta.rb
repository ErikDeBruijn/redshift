module RedShift
  
class Component

  @@flows = {}
  @@transitions = {}

  @@cached_flows = {}
  @@cached_flows_values = {}
  @@cached_transitions = {}
  @@cached_transitions_values = {}
  
  @@cached_states = {}
  @@cached_events = {}
  

  def Component.attach states, features
  
    if features.type != Array
      features = [features]
    end
    
    case states
      
      when State
        attach_flows [states], features
      
      when Array
        attach_flows states, features
      
      when Hash
        attach_transitions states, features
      
      else
        raise "Bad state list: #{states.inspect}"
    end
    
  end
  

  def Component.attach_flows states, new_flows
    flows = @@flows[self] ||= {}
    
    for state in states
      flows[state] ||= {}
      
      for f in new_flows
        flows[state][f.var] = f
        f.attach self, state
          # must be done before clearing cache -- see Flow#attach
      end
      
      for cl, in @@flows
        if cl <= self
          if @@cached_flows[cl]
            @@cached_flows[cl][state] = nil
          end
          @@cached_states[cl] = nil
        end
      end
      
    end
    
  end
  
  
  def Component.attach_transitions states, new_transitions
    transitions = @@transitions[self] ||= {}
    
    for src, dest in states
      transitions[src] ||= {}
      
      for t in new_transitions
        transitions[src][t.name] = [t, dest]
        for e in t.events
          e.attach self
        end
      end
      
      for cl, in @@transitions
        if cl <= self
          if @@cached_transitions[cl]
            @@cached_transitions[cl][src] = nil
          end
          @@cached_states[cl] = nil
          @@cached_events[cl] = nil
        end
      end
      
    end
    
  end
  
  
  def Component.cached_flows cl, state
    if @@cached_flows[cl] and
       @@cached_flows[cl][state]
      return @@cached_flows[cl][state]
    end
    
    if cl == Component
      flows = {}
    else
      flows = cached_flows(cl.superclass, state).dup
    end
    
    if @@flows[cl] and @@flows[cl][state]
      flows.update @@flows[cl][state]
    end
    
    (@@cached_flows_values[cl] ||= {})[state] = flows.values
    (@@cached_flows[cl] ||= {})[state] = flows
  end
  
  def Component.flows cl, state
    unless @@cached_flows[cl] and
           @@cached_flows[cl][state]
      cached_flows cl, state
    end
    @@cached_flows_values[cl][state]
  end  
  
  
  def Component.cached_transitions cl, state
    if @@cached_transitions[cl] and
       @@cached_transitions[cl][state]
      return @@cached_transitions[cl][state]
    end
    
    if cl == Component
      transitions = {}
    else
      transitions = cached_transitions(cl.superclass, state).dup
    end
    
    if @@transitions[cl] and @@transitions[cl][state]
      transitions.update @@transitions[cl][state]
    end
    
    (@@cached_transitions_values[cl] ||= {})[state] = transitions.values
    (@@cached_transitions[cl] ||= {})[state] = transitions
  end
  
  def Component.transitions cl, state
    unless @@cached_transitions[cl] and
           @@cached_transitions[cl][state]
      cached_transitions cl, state
    end
    @@cached_transitions_values[cl][state]
  end
  
  
  def Component.states cl
    if @@cached_states[cl]
      return @@cached_states[cl]
    end
    
    if cl == Component
      _states = []
    else
      _states = states(cl.superclass).dup
    end
    
    if @@flows[cl]
      @@flows[cl].each_key do |s|
        _states |= [s]
      end
    end
    
    if @@transitions[cl]
      @@transitions[cl].each do |s, h|
        _states |= [s]
        h.each_value do |t|
          _states |= [t[1]]
        end
      end
    end
    
    @@cached_states[cl] = _states
  end
  
    
  def Component.events cl, state
    if not @@cached_events[cl] or
       not @@cached_events[cl][state]
      @@cached_events[cl] ||= {}
      @@cached_events[cl][state] = []
      for t, d in transitions cl, state
        @@cached_events[cl][state] |= t.events
      end
    end
    
    @@cached_events[cl][state]
  end
  
  
  def flows state = @state
    Component.flows type, state
  end
  
  def transitions state = @state
    Component.transitions type, state
  end
  
  def states
    Component.states type    
  end
  
  def events state = @state
    Component.events type, state
  end
  
end # class Component

end # module RedShift
