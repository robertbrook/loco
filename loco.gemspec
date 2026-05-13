Gem::Specification.new do |spec|
  spec.name          = "loco"
  spec.version       = "0.1.0"
  spec.authors       = ["robertbrook"]
  spec.summary       = "A Logo interpreter in Ruby"
  spec.description   = "A Ruby implementation of the UCB Logo interpreter"
  spec.files         = Dir["lib/**/*", "bin/*", "README.md"]
  spec.executables   = ["loco"]
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 2.6"
  spec.add_development_dependency "minitest"
end
