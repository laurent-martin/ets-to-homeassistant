# frozen_string_literal: true

require_relative 'lib/ets_to_hass/info'

# expected extension of gemspec file
GEMSPEC_EXT = '.gemspec'
Gem::Specification.new do |spec|
  # get location of this file (shall be in project root)
  gemspec_file = File.expand_path(__FILE__)
  raise "Error: this file extension must be '#{GEMSPEC_EXT}'" unless gemspec_file.end_with?(GEMSPEC_EXT)
  raise "This file shall be named: #{EtsToHass::NAME}#{GEMSPEC_EXT}" unless
    EtsToHass::NAME.eql?(File.basename(gemspec_file, GEMSPEC_EXT).downcase)
  # the base name of this file shall be the gem name
  spec.name          = EtsToHass::NAME
  spec.version       = ENV.fetch('GEM_VERSION', EtsToHass::VERSION)
  spec.authors       = ['Laurent Martin']
  spec.email         = ['laurent.martin.l@gmail.com']
  spec.summary       = 'Tool to generate Home Assistant configuration from ETS project'
  spec.description   = 'Generate Home Assistant configuration from ETS project'
  spec.homepage      = EtsToHass::SRC_URL
  spec.license       = 'Apache-2.0'
  spec.requirements << 'Read the manual for any requirement'
  raise 'RubyGems 3.0 or newer is required' unless spec.respond_to?(:metadata)
  spec.metadata['allowed_push_host'] = 'https://rubygems.org' # push only to rubygems.org
  spec.metadata['homepage_uri']      = spec.homepage
  spec.metadata['source_code_uri']   = spec.homepage
  spec.metadata['changelog_uri']     = spec.homepage
  spec.metadata['rubygems_uri']      = EtsToHass::GEM_URL
  spec.metadata['documentation_uri'] = EtsToHass::DOC_URL
  spec.metadata['bug_tracker_uri']   = EtsToHass::SRC_URL
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.require_paths = ['lib']
  spec.bindir        = 'bin'
  # list git files from specified location in root folder of project (this gemspec is in project root folder)
  spec.files = Dir.chdir(File.dirname(gemspec_file)) { `git ls-files -z lib bin *.md`.split("\x0") }
  # specify executable names: must be after lines defining: spec.bindir and spec.files
  spec.executables = spec.files.grep(/^#{spec.bindir}/) { |f| File.basename(f) }
  spec.cert_chain  = ['certs/gem-public-cert.pem']
  spec.signing_key = File.expand_path(ENV.fetch('SIGNING_KEY')) if ENV.key?('SIGNING_KEY')
  spec.required_ruby_version = '>= 2.7'
  # dependency gems for runtime
  spec.add_runtime_dependency('base64', '~> 0.3.0')
  spec.add_runtime_dependency('clipboard', '~> 2.0.0')
  spec.add_runtime_dependency('csv')
  spec.add_runtime_dependency('ffi', '~> 1.9')
  spec.add_runtime_dependency('getoptlong')
  spec.add_runtime_dependency('glimmer-dsl-libui', '~> 0.12.8')
  spec.add_runtime_dependency('rubyzip', '~> 3.1')
  spec.add_runtime_dependency('xml-simple', '~> 1.0')

  # development gems
  spec.add_development_dependency('bundler', '~> 2.0')
  spec.add_development_dependency('debug', '~> 1.9')
  spec.add_development_dependency('rake', '~> 13.0')
  spec.add_development_dependency('reek', '~> 6.1.0')
  spec.add_development_dependency('rspec', '~> 3.0')
  spec.add_development_dependency('rubocop', '~> 1.12')
  spec.add_development_dependency('rubocop-ast', '~> 1.4')
  spec.add_development_dependency('rubocop-performance', '~> 1.10')
  spec.add_development_dependency('rubocop-shopify', '~> 2.0')
  spec.add_development_dependency('simplecov', '~> 0.18')
  spec.add_development_dependency('solargraph', '~> 0.44')
end
