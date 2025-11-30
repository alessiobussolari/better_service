require "bundler/setup"

require "bundler/gem_tasks"
require "rspec/core/rake_task"

# Default task runs RSpec
RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = "spec/**/*_spec.rb"
  t.exclude_pattern = "spec/rails_app/**/*"
end

task default: :spec
task test: :spec
