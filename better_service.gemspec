require_relative "lib/better_service/version"

Gem::Specification.new do |spec|
  spec.name        = "better_service"
  spec.version     = BetterService::VERSION
  spec.authors     = [ "alessiobussolari" ]
  spec.email       = [ "alessio.bussolari@pandev.it" ]
  spec.homepage    = "https://github.com/alessiobussolari/better_service"
  spec.summary     = "DSL-based Service Objects framework for Rails"
  spec.description = "A powerful DSL-based framework for building Service Objects in Rails with built-in support for validation, caching, presenters, and more."
  spec.license     = "WTFPL"

  spec.metadata["source_code_uri"] = "https://github.com/alessiobussolari/better_service"
  spec.metadata["changelog_uri"] = "https://github.com/alessiobussolari/better_service/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "LICENSE", "Rakefile", "README.md"]
  end

  spec.required_ruby_version = ">= 3.1.0"

  # Runtime dependencies
  spec.add_dependency "rails", "~> 8.1", ">= 8.1.1"
  spec.add_dependency "dry-schema", "~> 1.13"

  # Development dependencies
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rubocop-rails-omakase", "~> 1.0"
end
