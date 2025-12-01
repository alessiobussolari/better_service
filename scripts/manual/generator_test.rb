#!/usr/bin/env ruby
# frozen_string_literal: true

# Manual Generator Test Script for BetterService
#
# This script tests all BetterService generators by:
# 1. Running each generator in the dummy Rails app
# 2. Verifying generated files exist and have correct content
# 3. Cleaning up generated files after each test
# 4. Providing a detailed test report
#
# Usage:
#   cd spec/rails_app
#   rails runner ../../scripts/manual/generator_test.rb
#
# Or from project root:
#   cd spec/rails_app && rails runner ../../scripts/manual/generator_test.rb && cd ../..

require "fileutils"

class GeneratorTester
  COLORS = {
    red: "\e[31m",
    green: "\e[32m",
    yellow: "\e[33m",
    blue: "\e[34m",
    magenta: "\e[35m",
    cyan: "\e[36m",
    reset: "\e[0m"
  }.freeze

  def initialize
    @results = []
    @total_tests = 0
    @passed_tests = 0
    @failed_tests = 0
  end

  def run
    print_header

    # Test Serviceable generators
    test_serviceable_generators

    # Test Workflowable generator
    test_workflowable_generator

    # Test BetterService utility generators
    test_better_service_generators

    # Print final report
    print_report
  end

  private

  def test_serviceable_generators
    section_header("Testing Serviceable Generators")

    # Test individual CRUD generators
    test_index_generator
    test_show_generator
    test_create_generator
    test_update_generator
    test_destroy_generator

    # Test action generator
    test_action_generator

    # Test scaffold generator
    test_scaffold_generator
  end

  def test_workflowable_generator
    section_header("Testing Workflowable Generator")

    test_workflow_generator
  end

  def test_better_service_generators
    section_header("Testing BetterService Utility Generators")

    test_locale_generator
    test_presenter_generator
  end

  def test_index_generator
    test_name = "serviceable:index generator"
    puts colorize("\n▶ Testing #{test_name}...", :cyan)

    cleanup_service_files("Product", "index")

    # Run generator
    success = run_generator("serviceable:index Product")
    return record_failure(test_name, "Generator command failed") unless success

    # Verify service file
    service_file = "app/services/product/index_service.rb"
    unless file_exists?(service_file)
      cleanup_service_files("Product", "index")
      return record_failure(test_name, "Service file not created: #{service_file}")
    end

    # Verify service content
    service_content = File.read(service_file)
    checks = [
      [ service_content.include?("class Product::IndexService"), "Missing class definition" ],
      [ service_content.include?("< BetterService::Services::Base"), "Wrong base class" ],
      [ service_content.include?("performed_action :listed"), "Missing action_name" ],
      [ service_content.include?("schema do"), "Missing schema block" ],
      [ service_content.include?("optional(:page)"), "Missing pagination params" ]
    ]

    failed_check = checks.find { |check, _| !check }
    if failed_check
      cleanup_service_files("Product", "index")
      return record_failure(test_name, failed_check[1])
    end

    # Verify test file
    test_file = "test/services/product/index_service_test.rb"
    unless file_exists?(test_file)
      cleanup_service_files("Product", "index")
      return record_failure(test_name, "Test file not created: #{test_file}")
    end

    # Cleanup
    cleanup_service_files("Product", "index")

    record_success(test_name)
  end

  def test_show_generator
    test_name = "serviceable:show generator"
    puts colorize("\n▶ Testing #{test_name}...", :cyan)

    cleanup_service_files("Product", "show")

    success = run_generator("serviceable:show Product")
    return record_failure(test_name, "Generator command failed") unless success

    service_file = "app/services/product/show_service.rb"
    unless file_exists?(service_file)
      cleanup_service_files("Product", "show")
      return record_failure(test_name, "Service file not created")
    end

    service_content = File.read(service_file)
    checks = [
      [ service_content.include?("class Product::ShowService"), "Missing class definition" ],
      [ service_content.include?("< BetterService::Services::Base"), "Wrong base class" ],
      [ service_content.include?("performed_action :showed"), "Missing action_name" ],
      [ service_content.include?("required(:id)"), "Missing id param" ]
    ]

    failed_check = checks.find { |check, _| !check }
    if failed_check
      cleanup_service_files("Product", "show")
      return record_failure(test_name, failed_check[1])
    end

    test_file = "test/services/product/show_service_test.rb"
    unless file_exists?(test_file)
      cleanup_service_files("Product", "show")
      return record_failure(test_name, "Test file not created")
    end

    cleanup_service_files("Product", "show")
    record_success(test_name)
  end

  def test_create_generator
    test_name = "serviceable:create generator"
    puts colorize("\n▶ Testing #{test_name}...", :cyan)

    cleanup_service_files("Product", "create")

    success = run_generator("serviceable:create Product")
    return record_failure(test_name, "Generator command failed") unless success

    service_file = "app/services/product/create_service.rb"
    unless file_exists?(service_file)
      cleanup_service_files("Product", "create")
      return record_failure(test_name, "Service file not created")
    end

    service_content = File.read(service_file)
    checks = [
      [ service_content.include?("class Product::CreateService"), "Missing class definition" ],
      [ service_content.include?("< BetterService::Services::Base"), "Wrong base class" ],
      [ service_content.include?("performed_action :created"), "Missing action_name" ],
      [ service_content.include?("with_transaction true"), "Missing transaction" ]
    ]

    failed_check = checks.find { |check, _| !check }
    if failed_check
      cleanup_service_files("Product", "create")
      return record_failure(test_name, failed_check[1])
    end

    test_file = "test/services/product/create_service_test.rb"
    unless file_exists?(test_file)
      cleanup_service_files("Product", "create")
      return record_failure(test_name, "Test file not created")
    end

    cleanup_service_files("Product", "create")
    record_success(test_name)
  end

  def test_update_generator
    test_name = "serviceable:update generator"
    puts colorize("\n▶ Testing #{test_name}...", :cyan)

    cleanup_service_files("Product", "update")

    success = run_generator("serviceable:update Product")
    return record_failure(test_name, "Generator command failed") unless success

    service_file = "app/services/product/update_service.rb"
    unless file_exists?(service_file)
      cleanup_service_files("Product", "update")
      return record_failure(test_name, "Service file not created")
    end

    service_content = File.read(service_file)
    checks = [
      [ service_content.include?("class Product::UpdateService"), "Missing class definition" ],
      [ service_content.include?("< BetterService::Services::Base"), "Wrong base class" ],
      [ service_content.include?("performed_action :updated"), "Missing action_name" ],
      [ service_content.include?("with_transaction true"), "Missing transaction" ],
      [ service_content.include?("required(:id)"), "Missing id param" ]
    ]

    failed_check = checks.find { |check, _| !check }
    if failed_check
      cleanup_service_files("Product", "update")
      return record_failure(test_name, failed_check[1])
    end

    test_file = "test/services/product/update_service_test.rb"
    unless file_exists?(test_file)
      cleanup_service_files("Product", "update")
      return record_failure(test_name, "Test file not created")
    end

    cleanup_service_files("Product", "update")
    record_success(test_name)
  end

  def test_destroy_generator
    test_name = "serviceable:destroy generator"
    puts colorize("\n▶ Testing #{test_name}...", :cyan)

    cleanup_service_files("Product", "destroy")

    success = run_generator("serviceable:destroy Product")
    return record_failure(test_name, "Generator command failed") unless success

    service_file = "app/services/product/destroy_service.rb"
    unless file_exists?(service_file)
      cleanup_service_files("Product", "destroy")
      return record_failure(test_name, "Service file not created")
    end

    service_content = File.read(service_file)
    checks = [
      [ service_content.include?("class Product::DestroyService"), "Missing class definition" ],
      [ service_content.include?("< BetterService::Services::Base"), "Wrong base class" ],
      [ service_content.include?("performed_action :destroyed"), "Missing action_name" ],
      [ service_content.include?("with_transaction true"), "Missing transaction" ],
      [ service_content.include?("required(:id)"), "Missing id param" ]
    ]

    failed_check = checks.find { |check, _| !check }
    if failed_check
      cleanup_service_files("Product", "destroy")
      return record_failure(test_name, failed_check[1])
    end

    test_file = "test/services/product/destroy_service_test.rb"
    unless file_exists?(test_file)
      cleanup_service_files("Product", "destroy")
      return record_failure(test_name, "Test file not created")
    end

    cleanup_service_files("Product", "destroy")
    record_success(test_name)
  end

  def test_action_generator
    test_name = "serviceable:action generator"
    puts colorize("\n▶ Testing #{test_name}...", :cyan)

    cleanup_service_files("Product", "approve")

    success = run_generator("serviceable:action Product approve")
    return record_failure(test_name, "Generator command failed") unless success

    service_file = "app/services/product/approve_service.rb"
    unless file_exists?(service_file)
      cleanup_service_files("Product", "approve")
      return record_failure(test_name, "Service file not created")
    end

    service_content = File.read(service_file)
    checks = [
      [ service_content.include?("class Product::ApproveService"), "Missing class definition" ],
      [ service_content.include?("< BetterService::Services::Base"), "Wrong base class" ],
      [ service_content.include?("performed_action :approve"), "Missing action_name" ]
    ]

    failed_check = checks.find { |check, _| !check }
    if failed_check
      cleanup_service_files("Product", "approve")
      return record_failure(test_name, failed_check[1])
    end

    test_file = "test/services/product/approve_service_test.rb"
    unless file_exists?(test_file)
      cleanup_service_files("Product", "approve")
      return record_failure(test_name, "Test file not created")
    end

    cleanup_service_files("Product", "approve")
    record_success(test_name)
  end

  def test_scaffold_generator
    test_name = "serviceable:scaffold generator"
    puts colorize("\n▶ Testing #{test_name}...", :cyan)

    cleanup_scaffold_files("TestModel")

    success = run_generator("serviceable:scaffold TestModel")
    return record_failure(test_name, "Generator command failed") unless success

    # Check all 5 CRUD services were created
    services = %w[index show create update destroy]
    services.each do |service_type|
      service_file = "app/services/test_model/#{service_type}_service.rb"
      unless file_exists?(service_file)
        cleanup_scaffold_files("TestModel")
        return record_failure(test_name, "Missing #{service_type} service file")
      end

      test_file = "test/services/test_model/#{service_type}_service_test.rb"
      unless file_exists?(test_file)
        cleanup_scaffold_files("TestModel")
        return record_failure(test_name, "Missing #{service_type} test file")
      end
    end

    # Verify class names are correct
    create_service = File.read("app/services/test_model/create_service.rb")
    unless create_service.include?("class TestModel::CreateService")
      cleanup_scaffold_files("TestModel")
      return record_failure(test_name, "Incorrect class name in generated service")
    end

    cleanup_scaffold_files("TestModel")
    record_success(test_name)
  end

  def test_workflow_generator
    test_name = "workflowable:workflow generator"
    puts colorize("\n▶ Testing #{test_name}...", :cyan)

    cleanup_workflow_files("OrderProcessing")

    success = run_generator("workflowable:workflow OrderProcessing --steps create_order charge_payment")
    return record_failure(test_name, "Generator command failed") unless success

    workflow_file = "app/workflows/order_processing_workflow.rb"
    unless file_exists?(workflow_file)
      cleanup_workflow_files("OrderProcessing")
      return record_failure(test_name, "Workflow file not created")
    end

    workflow_content = File.read(workflow_file)
    checks = [
      [ workflow_content.include?("class OrderProcessingWorkflow"), "Missing class definition" ],
      [ workflow_content.include?("< BetterService::Workflow"), "Wrong base class" ],
      [ workflow_content.include?("step :create_order"), "Missing create_order step" ],
      [ workflow_content.include?("step :charge_payment"), "Missing charge_payment step" ]
    ]

    failed_check = checks.find { |check, _| !check }
    if failed_check
      cleanup_workflow_files("OrderProcessing")
      return record_failure(test_name, failed_check[1])
    end

    test_file = "test/workflows/order_processing_workflow_test.rb"
    unless file_exists?(test_file)
      cleanup_workflow_files("OrderProcessing")
      return record_failure(test_name, "Test file not created")
    end

    cleanup_workflow_files("OrderProcessing")
    record_success(test_name)
  end

  def test_locale_generator
    test_name = "better_service:locale generator"
    puts colorize("\n▶ Testing #{test_name}...", :cyan)

    cleanup_locale_files("products")

    success = run_generator("better_service:locale products")
    return record_failure(test_name, "Generator command failed") unless success

    locale_file = "config/locales/products_services.en.yml"
    unless file_exists?(locale_file)
      cleanup_locale_files("products")
      return record_failure(test_name, "Locale file not created: #{locale_file}")
    end

    locale_content = File.read(locale_file)
    checks = [
      [ locale_content.include?("en:"), "Missing en: root key" ],
      [ locale_content.include?("products:"), "Missing products namespace" ],
      [ locale_content.include?("services:"), "Missing services key" ],
      [ locale_content.include?("create:"), "Missing create action" ],
      [ locale_content.include?("update:"), "Missing update action" ],
      [ locale_content.include?("destroy:"), "Missing destroy action" ],
      [ locale_content.include?("index:"), "Missing index action" ],
      [ locale_content.include?("show:"), "Missing show action" ],
      [ locale_content.include?("success:"), "Missing success messages" ],
      [ locale_content.include?("failure:"), "Missing failure messages" ]
    ]

    failed_check = checks.find { |check, _| !check }
    if failed_check
      cleanup_locale_files("products")
      return record_failure(test_name, failed_check[1])
    end

    # Verify valid YAML
    begin
      YAML.safe_load(locale_content)
    rescue StandardError => e
      cleanup_locale_files("products")
      return record_failure(test_name, "Invalid YAML: #{e.message}")
    end

    cleanup_locale_files("products")
    record_success(test_name)
  end

  def test_presenter_generator
    test_name = "better_service:presenter generator"
    puts colorize("\n▶ Testing #{test_name}...", :cyan)

    cleanup_presenter_files("Product")

    success = run_generator("better_service:presenter Product")
    return record_failure(test_name, "Generator command failed") unless success

    # Verify presenter file
    presenter_file = "app/presenters/product_presenter.rb"
    unless file_exists?(presenter_file)
      cleanup_presenter_files("Product")
      return record_failure(test_name, "Presenter file not created: #{presenter_file}")
    end

    presenter_content = File.read(presenter_file)
    checks = [
      [ presenter_content.include?("class ProductPresenter"), "Missing class definition" ],
      [ presenter_content.include?("< BetterService::Presenter"), "Wrong base class" ],
      [ presenter_content.include?("def as_json(opts = {})"), "Missing as_json method" ],
      [ presenter_content.include?("object"), "Missing object reference" ]
    ]

    failed_check = checks.find { |check, _| !check }
    if failed_check
      cleanup_presenter_files("Product")
      return record_failure(test_name, failed_check[1])
    end

    # Verify test file
    test_file = "test/presenters/product_presenter_test.rb"
    unless file_exists?(test_file)
      cleanup_presenter_files("Product")
      return record_failure(test_name, "Test file not created: #{test_file}")
    end

    test_content = File.read(test_file)
    test_checks = [
      [ test_content.include?("class ProductPresenterTest"), "Missing test class" ],
      [ test_content.include?("< ActiveSupport::TestCase"), "Wrong test base class" ],
      [ test_content.include?("@presenter"), "Missing presenter instance" ],
      [ test_content.include?("as_json"), "Missing as_json tests" ],
      [ test_content.include?("options"), "Missing options tests" ]
    ]

    failed_test_check = test_checks.find { |check, _| !check }
    if failed_test_check
      cleanup_presenter_files("Product")
      return record_failure(test_name, failed_test_check[1])
    end

    cleanup_presenter_files("Product")
    record_success(test_name)
  end

  # Helper methods

  def run_generator(command)
    output = `rails generate #{command} 2>&1`
    $?.success?
  end

  def file_exists?(path)
    File.exist?(path)
  end

  def cleanup_service_files(model, service_type)
    model_dir = model.underscore
    service_file = "app/services/#{model_dir}/#{service_type}_service.rb"
    test_file = "test/services/#{model_dir}/#{service_type}_service_test.rb"

    FileUtils.rm_f(service_file)
    FileUtils.rm_f(test_file)

    # Remove directory if empty
    service_dir = "app/services/#{model_dir}"
    FileUtils.rmdir(service_dir) if Dir.exist?(service_dir) && Dir.empty?(service_dir)

    test_dir = "test/services/#{model_dir}"
    FileUtils.rmdir(test_dir) if Dir.exist?(test_dir) && Dir.empty?(test_dir)
  end

  def cleanup_scaffold_files(model)
    model_dir = model.underscore
    service_types = %w[index show create update destroy]

    service_types.each do |service_type|
      cleanup_service_files(model, service_type)
    end
  end

  def cleanup_workflow_files(workflow_name)
    workflow_file = "app/workflows/#{workflow_name.underscore}_workflow.rb"
    test_file = "test/workflows/#{workflow_name.underscore}_workflow_test.rb"

    FileUtils.rm_f(workflow_file)
    FileUtils.rm_f(test_file)

    # Remove directories if empty
    FileUtils.rmdir("app/workflows") if Dir.exist?("app/workflows") && Dir.empty?("app/workflows")
    FileUtils.rmdir("test/workflows") if Dir.exist?("test/workflows") && Dir.empty?("test/workflows")
  end

  def cleanup_locale_files(namespace)
    locale_file = "config/locales/#{namespace}_services.en.yml"
    FileUtils.rm_f(locale_file)
  end

  def cleanup_presenter_files(model)
    model_name = model.underscore
    presenter_file = "app/presenters/#{model_name}_presenter.rb"
    test_file = "test/presenters/#{model_name}_presenter_test.rb"

    FileUtils.rm_f(presenter_file)
    FileUtils.rm_f(test_file)

    # Remove directories if empty
    FileUtils.rmdir("app/presenters") if Dir.exist?("app/presenters") && Dir.empty?("app/presenters")
    FileUtils.rmdir("test/presenters") if Dir.exist?("test/presenters") && Dir.empty?("test/presenters")
  end

  def record_success(test_name)
    @total_tests += 1
    @passed_tests += 1
    @results << { name: test_name, status: :passed }
    puts colorize("  ✓ PASSED", :green)
  end

  def record_failure(test_name, reason)
    @total_tests += 1
    @failed_tests += 1
    @results << { name: test_name, status: :failed, reason: reason }
    puts colorize("  ✗ FAILED: #{reason}", :red)
  end

  def print_header
    puts colorize("\n" + "=" * 80, :blue)
    puts colorize("  BetterService Generator Manual Test Suite", :blue)
    puts colorize("=" * 80 + "\n", :blue)
  end

  def section_header(title)
    puts colorize("\n" + "-" * 80, :magenta)
    puts colorize("  #{title}", :magenta)
    puts colorize("-" * 80, :magenta)
  end

  def print_report
    puts colorize("\n" + "=" * 80, :blue)
    puts colorize("  Test Report", :blue)
    puts colorize("=" * 80 + "\n", :blue)

    @results.each do |result|
      status_symbol = result[:status] == :passed ? "✓" : "✗"
      status_color = result[:status] == :passed ? :green : :red
      status_text = result[:status] == :passed ? "PASSED" : "FAILED"

      puts colorize("  #{status_symbol} #{result[:name]}", status_color)
      puts colorize("      Reason: #{result[:reason]}", :red) if result[:reason]
    end

    puts colorize("\n" + "-" * 80, :blue)
    puts colorize("  Total Tests: #{@total_tests}", :blue)
    puts colorize("  Passed: #{@passed_tests}", :green)
    puts colorize("  Failed: #{@failed_tests}", @failed_tests > 0 ? :red : :green)
    puts colorize("  Success Rate: #{success_rate}%", success_rate == 100 ? :green : :yellow)
    puts colorize("=" * 80 + "\n", :blue)

    if @failed_tests == 0
      puts colorize("🎉 All tests passed!", :green)
    else
      puts colorize("⚠️  Some tests failed. Please review the failures above.", :red)
    end
  end

  def success_rate
    return 0 if @total_tests == 0
    ((@passed_tests.to_f / @total_tests) * 100).round(2)
  end

  def colorize(text, color)
    "#{COLORS[color]}#{text}#{COLORS[:reset]}"
  end
end

# Run the tests
if __FILE__ == $PROGRAM_NAME || caller.any? { |line| line.include?("rails/commands/runner") }
  tester = GeneratorTester.new
  tester.run
end
