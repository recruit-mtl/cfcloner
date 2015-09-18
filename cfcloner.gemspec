# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cfcloner/version'

Gem::Specification.new do |spec|
  spec.name          = "cfcloner"
  spec.version       = Cfcloner::VERSION
  spec.authors       = ["Media Technology Lab"]
  spec.email         = ["support@mtl.recruit.co.jp"]

  spec.summary       = %q{This is a gem that clone CloudFront.}
  spec.description   = %q{This gem can convert CloudFront configs to varnish config language. Please set your credentials and write CloudFront instance ID in "cfcloner.rb".}
  spec.homepage      = "https://github.com/recruit-mtl/cfcloner"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org by setting 'allowed_push_host', or
  # delete this section to allow pushing this gem to any host.
  # if spec.respond_to?(:metadata)
  #   spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  # else
  #   raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  # end

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "aws-sdk", "2.1.18"

  spec.add_development_dependency "bundler", "~> 1.10"
  spec.add_development_dependency "rake", "~> 10.0"
  # spec.add_development_dependency "aws-sdk", "~> 2.0.0"
  spec.add_development_dependency "aws-sdk", "2.1.18"

end
