# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'db_sucker/version'

Gem::Specification.new do |spec|
  spec.name          = "db_sucker"
  spec.version       = DbSucker::VERSION
  spec.authors       = ["Sven Pachnit"]
  spec.email         = ["sven@bmonkeys.net"]
  spec.summary       = %q{Sucks all your remote MySQL databases via SSH for local tampering.}
  spec.description   = %q{Suck whole databases, tables and even incremental updates and save your presets for easy reuse.}
  spec.homepage      = "https://github.com/2called-chaos/db_sucker"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake"
  spec.add_dependency "activesupport"
  spec.add_dependency "pry"
  spec.add_dependency "net-ssh"
  spec.add_dependency "net-sftp"
end
