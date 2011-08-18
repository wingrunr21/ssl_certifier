# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "ssl_certifier/version"

Gem::Specification.new do |s|
  s.name        = "ssl_certifier"
  s.version     = SslCertifier::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Stafford Brunk"]
  s.email       = ["wingrunr21@gmail.com"]
  s.homepage    = "https://www.github.com/wingrunr21/ssl_certifier"
  s.summary     = %q{Adds root certificates to the OpenURI module so that SSL connections work properly in Ruby 1.9}
  s.description = %q{Adds root certificates to the OpenURI module so that SSL connections work properly in Ruby 1.9.  This gem allows for SSL connections to function properly even when Ruby does not have access to the operating system's default root certificates}

  s.rubyforge_project = "ssl_certifier"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_development_dependency "rspec", "~> 2.6.0"
end
