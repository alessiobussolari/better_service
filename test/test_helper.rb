# Code Coverage - must be loaded before application code
if ENV["COVERAGE"]
  require "simplecov"
  require "simplecov-cobertura"

  SimpleCov.start do
    add_filter "/test/"
    add_filter "/test/dummy/"
    add_filter "/lib/generators/"

    add_group "Services", "lib/better_service/services"
    add_group "Concerns", "lib/better_service/concerns"
    add_group "Workflows", "lib/better_service/workflows"
    add_group "Repository", "lib/better_service/repository"
    add_group "Errors", "lib/better_service/errors"

    formatter SimpleCov::Formatter::MultiFormatter.new([
      SimpleCov::Formatter::HTMLFormatter,
      SimpleCov::Formatter::CoberturaFormatter
    ])

    minimum_coverage 80
  end
end

# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require_relative "../test/dummy/config/environment"
ActiveRecord::Migrator.migrations_paths = [ File.expand_path("../test/dummy/db/migrate", __dir__) ]
require "rails/test_help"

# Load fixtures from the engine
if ActiveSupport::TestCase.respond_to?(:fixture_paths=)
  ActiveSupport::TestCase.fixture_paths = [ File.expand_path("fixtures", __dir__) ]
  ActionDispatch::IntegrationTest.fixture_paths = ActiveSupport::TestCase.fixture_paths
  ActiveSupport::TestCase.file_fixture_path = File.expand_path("fixtures", __dir__) + "/files"
  ActiveSupport::TestCase.fixtures :all
end
