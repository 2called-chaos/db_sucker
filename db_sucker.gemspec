# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'db_sucker/version'

Gem::Specification.new do |spec|
  spec.name          = "db_sucker"
  spec.version       = DbSucker::VERSION
  spec.authors       = ["Sven Pachnit"]
  spec.email         = ["sven@bmonkeys.net"]
  spec.summary       = %q{Sucks your remote databases via SSH for local tampering.}
  spec.description   = %q{Suck whole databases, tables and even incremental updates and save your presets for easy reuse.}
  spec.homepage      = "https://github.com/2called-chaos/db_sucker"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "curses", "~> 1.2"
  spec.add_dependency "activesupport", ">= 4.1"
  spec.add_dependency "net-ssh", "~> 7.0"
  spec.add_dependency "ed25519", ">= 1.2", "< 2.0"
  spec.add_dependency "bcrypt_pbkdf", ">= 1.0", "< 2.0"
  spec.add_dependency "net-sftp", "~> 4.0"
  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "pry-remote"
end
