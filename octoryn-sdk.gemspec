# frozen_string_literal: true

require_relative 'lib/octoryn/version'

Gem::Specification.new do |spec|
  spec.name = 'octoryn-sdk'
  spec.version = Octoryn::VERSION
  spec.authors = ['Octopus Core Pty Ltd']
  spec.email = ['support@octoryn.dev']
  spec.summary = 'Governed AI SDK for Octoryn Router'
  spec.homepage = 'https://octoryn.dev'
  spec.license = 'Apache-2.0'
  spec.required_ruby_version = '>= 3.2'
  spec.files = Dir['lib/**/*.rb', 'README.md', 'LICENSE']
  spec.require_paths = ['lib']
  spec.metadata = {
    'source_code_uri' => 'https://github.com/octoryn/octoryn-ruby',
    'documentation_uri' => 'https://octoryn.dev/docs',
    'rubygems_mfa_required' => 'true'
  }
  spec.add_dependency 'json_schemer', '~> 2.4'
end
