require 'redshift'

Gem::Specification.new do |s|
  s.name = "redshift"
  s.version = RedShift::VERSION

  s.required_rubygems_version = Gem::Requirement.new(">= 0")
  s.add_dependency('cgen', '~> 0')
  s.add_dependency('tkar', '~> 0')
  s.add_dependency('prng-isaac', '~> 0')
  s.authors = ["Joel VanderWerf"]
  s.date = Time.now.strftime "%Y-%m-%d"
  s.summary = "Simulation of hybrid automata"
  s.description = "A framework for simulation of networks of hybrid automata, similar to SHIFT and Lambda-SHIFT. Includes ruby-based DSL for defining simulation components, and ruby/C code generation and runtime."
  s.email = "vjoel@users.sourceforge.net"
  s.extensions = [
    "ext/redshift/buffer/extconf.rb",
    "ext/redshift/dvector/extconf.rb",
    "ext/redshift/dvector-float/extconf.rb"
  ]
  s.extra_rdoc_files = ["README.md", "RELEASE-NOTES"]
  s.files = Dir[
    "Rakefile",
    "README.md", "RELEASE-NOTES",
    "bench/{bench,diff-bench,run,*.rb}",
    "examples/*.rb",
    "examples/robots/lib/*.rb",
    "examples/robots/robots.rb",
    "examples/robots/README",
    "examples/simulink/**/*",
    "ext/**/*.{c,h,rb}",
    "lib/**/*.rb",
    "test/*.rb"
  ]
  s.homepage = "https://github.com/vjoel/redshift"
  s.rdoc_options = ["--quiet", "--line-numbers", "--inline-source", "--title", "RedShift", "--main", "README.md", "--output", "rdoc"]
  s.require_paths = ["lib", "ext"]
end
