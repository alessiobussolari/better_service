# frozen_string_literal: true

require "bundler/setup"

ENV["RAILS_ENV"] ||= "test"

# Only initialize Rails if not already initialized (avoids FrozenError in CI)
unless defined?(Rails) && Rails.application&.initialized?
  require_relative "../config/environment"
end

require "rspec/rails"

# Require support files
Dir[Rails.root.join("spec/support/**/*.rb")].each { |f| require f }

# Configure BetterService for tests
BetterService.configure do |config|
  config.instrumentation_enabled = false
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.order = :random

  Kernel.srand config.seed

  # Use ActiveRecord transactions for cleanup
  config.use_transactional_fixtures = true

  # Include ActiveRecord fixtures support
  config.fixture_path = Rails.root.join("spec/fixtures")
end
