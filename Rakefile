require "bundler/setup"

require "bundler/gem_tasks"
require "rake/testtask"
require "fileutils"

# Track files created during test setup
CREATED_FILES_MARKER = ".test_created_files"
PRODUCT_SERVICES_DIR = "test/dummy/app/services/product"

# Service file templates
SERVICE_TEMPLATES = {
  "create_service.rb" => <<~RUBY,
    # frozen_string_literal: true

    class Product::CreateService < BetterService::Services::Base
      # Action name for metadata
      performed_action :created

      # Enable transaction wrapping
      with_transaction true

      # Schema for validating params
      schema do
        required(:name).filled(:string)
        required(:price).filled(:decimal, gt?: 0)
        optional(:published).filled(:bool)
      end

      # Phase 1: Search - Prepare dependencies (optional)
      search_with do
        {}
      end

      # Phase 2: Process - Create the resource
      process_with do |data|
        product = user.products.create!(params)
        { resource: product }
      end

      # Phase 4: Respond - Format response (optional override)
      respond_with do |data|
        success_result("Product created successfully", data)
      end
    end
  RUBY
  "index_service.rb" => <<~RUBY,
    # frozen_string_literal: true

    class Product::IndexService < BetterService::Services::Base
      # Action name for metadata
      performed_action :listed

      # Schema for validating params
      schema do
        optional(:page).filled(:integer, gteq?: 1)
        optional(:per_page).filled(:integer, gteq?: 1, lteq?: 100)
        optional(:search).maybe(:string)
      end

      # Phase 1: Search - Load raw data
      search_with do
        products = user.products
        products = products.where("name LIKE ?", "%\#{params[:search]}%") if params[:search].present?

        { items: products.to_a }
      end

      # Phase 2: Process - Transform and aggregate data
      process_with do |data|
        {
          items: data[:items],
          metadata: {
            stats: {
              total: data[:items].count
            },
            pagination: {
              page: params[:page] || 1,
              per_page: params[:per_page] || 25
            }
          }
        }
      end

      # Phase 4: Respond - Format response (optional override)
      respond_with do |data|
        success_result("Products loaded successfully", data)
      end
    end
  RUBY
  "show_service.rb" => <<~RUBY,
    # frozen_string_literal: true

    class Product::ShowService < BetterService::Services::Base
      # Action name for metadata
      performed_action :showed

      # Schema for validating params
      schema do
        required(:id).filled
      end

      # Phase 1: Search - Load the resource
      search_with do
        { resource: user.products.find(params[:id]) }
      end

      # Phase 4: Respond - Format response (optional override)
      respond_with do |data|
        success_result("Product loaded successfully", data)
      end
    end
  RUBY
  "update_service.rb" => <<~RUBY,
    # frozen_string_literal: true

    class Product::UpdateService < BetterService::Services::Base
      # Action name for metadata
      performed_action :updated

      # Enable transaction wrapping
      with_transaction true

      # Schema for validating params
      schema do
        required(:id).filled
      end

      # Phase 1: Search - Load the resource
      search_with do
        { resource: user.products.find(params[:id]) }
      end

      # Phase 2: Process - Update the resource
      process_with do |data|
        product = data[:resource]
        product.update!(params.except(:id))
        { resource: product }
      end

      # Phase 4: Respond - Format response (optional override)
      respond_with do |data|
        success_result("Product updated successfully", data)
      end
    end
  RUBY
  "destroy_service.rb" => <<~RUBY
    # frozen_string_literal: true

    class Product::DestroyService < BetterService::Services::Base
      # Action name for metadata
      performed_action :destroyed

      # Enable transaction wrapping
      with_transaction true

      # Schema for validating params
      schema do
        required(:id).filled
      end

      # Phase 1: Search - Load the resource
      search_with do
        { resource: user.products.find(params[:id]) }
      end

      # Phase 2: Process - Delete the resource
      process_with do |data|
        product = data[:resource]
        product.destroy!
        { resource: product }
      end

      # Phase 4: Respond - Format response (optional override)
      respond_with do |data|
        success_result("Product deleted successfully", data)
      end
    end
  RUBY
}

namespace :test do
  desc "Setup test environment - create missing Product service files"
  task :setup do
    created_files = []

    SERVICE_TEMPLATES.each do |filename, content|
      filepath = File.join(PRODUCT_SERVICES_DIR, filename)

      unless File.exist?(filepath)
        puts "Creating temporary test file: #{filepath}"
        File.write(filepath, content)
        created_files << filepath
      end
    end

    # Save list of created files
    File.write(CREATED_FILES_MARKER, created_files.join("\n")) if created_files.any?
    puts "Test setup complete (#{created_files.size} files created)" if created_files.any?
  end

  desc "Cleanup test environment - remove temporary Product service files"
  task :cleanup do
    if File.exist?(CREATED_FILES_MARKER)
      created_files = File.read(CREATED_FILES_MARKER).split("\n")

      created_files.each do |filepath|
        if File.exist?(filepath)
          puts "Removing temporary test file: #{filepath}"
          File.delete(filepath)
        end
      end

      File.delete(CREATED_FILES_MARKER)
      puts "Test cleanup complete (#{created_files.size} files removed)" if created_files.any?
    end
  end
end

Rake::TestTask.new(:test_only) do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"].exclude(
    "test/dummy/**/*",
    "test/generators/**/*",  # Generator tests require Rails context - run manually with: bundle exec ruby -Itest test/generators/*_test.rb
    "test/tmp/**/*"          # Temporary files from generator tests
  )
  t.verbose = false
end

# Main test task with automatic setup and cleanup
task :test do
  begin
    Rake::Task["test:setup"].invoke
    Rake::Task["test_only"].invoke
  ensure
    Rake::Task["test:cleanup"].invoke
  end
end

task default: :test
