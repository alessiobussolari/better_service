require "bundler/setup"

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"].exclude(
    "test/dummy/**/*",
    "test/generators/**/*"  # Generator tests require Rails context - run manually with: bundle exec ruby -Itest test/generators/*_test.rb
  )
  t.verbose = false
end

task default: :test
