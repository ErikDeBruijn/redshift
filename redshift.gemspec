Gem::Specification.new do |s|
  s.name = "redshift"
  s.version = "1.3.26"

  s.required_rubygems_version = Gem::Requirement.new(">= 0")
  s.authors = ["Joel VanderWerf"]
  s.date = "2013-04-05"
  s.description = "A framework for simulation of networks of hybrid automata, similar to SHIFT and Lambda-SHIFT. Includes ruby-based DSL for defining simulation components, and ruby/C code generation and runtime."
  s.email = "vjoel@users.sourceforge.net"
  s.extensions = ["ext/redshift/buffer/extconf.rb", "ext/redshift/dvector/extconf.rb", "ext/redshift/util/isaac/extconf.rb"]
  s.extra_rdoc_files = ["README.md", "RELEASE-NOTES"]
  s.files = Dir[
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
  s.homepage = "http://rubyforge.org/projects/redshift"
  s.rdoc_options = ["--quiet", "--line-numbers", "--inline-source", "--title", "CGenerator", "--main", "README.md"]
  s.require_paths = ["lib", "ext"]
  s.rubyforge_project = "redshift"
  s.rubygems_version = "2.0.3"
  s.summary = "Simulation of hybrid automata"
end
