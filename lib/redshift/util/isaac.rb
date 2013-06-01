require 'isaac'

# Adaptor class to use ISAAC with redshift/util/random distributions.
# See test/test_flow_trans.rb for an example.
class ISAACGenerator < PRNG::ISAAC
  def initialize(*seeds)
    super()
    if seeds.compact.empty?
      if defined?(RandomDistribution::Sequence.random_seed)
        seeds = [RandomDistribution::Sequence.random_seed]
      else
        seeds = [rand]
      end
    end
    @seeds = seeds
    srand(seeds)
  end
  
  attr_reader :seeds

  alias next rand
end
