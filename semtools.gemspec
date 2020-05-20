
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "semtools/version"

Gem::Specification.new do |spec|
  spec.name          = "semtools"
  spec.version       = Semtools::VERSION
  spec.authors       = ["seoanezonjic", "fmjabato"]
  spec.email         = ["seoanezonjic@hotmail.com", "fmjabato@gmail.com"]

  spec.summary       = %q{Gem to handle semantic based calculations in text and defined ontologies as GO or HPO.}
  spec.description   = %q{This gem allows to perform ontology based operations and calculation of Semantic similarity and information coefficient using different implementations.}
  spec.homepage      = "https://github.com/seoanezonjic/semtools"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  
  spec.add_dependency "text"

  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
