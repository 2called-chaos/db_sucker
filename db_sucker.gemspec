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

  spec.add_dependency "curses"
  spec.add_dependency "activesupport" #, "~> 4.2"
  spec.add_dependency "pry" #, "~> 0.10"
  spec.add_dependency "net-ssh" #, "~> 2.9"
  spec.add_dependency "net-sftp" #, "~> 2.1"
  spec.add_development_dependency "bundler" #, "~> 1.5"
  spec.add_development_dependency "rake" #, "~> 10.4"
end
