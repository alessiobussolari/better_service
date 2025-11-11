# frozen_string_literal: true

# Manual Testing Script per BetterService
#
# IMPORTANT: This file is wrapped in a transaction with automatic rollback
# to prevent database pollution. All changes made during this script are
# automatically rolled back when the script completes.
#
# HOW TO USE:
#   cd test/dummy
#   rails console
#   load '../../manual_test.rb'
#
# NOTE: This file should NOT be auto-loaded during the test suite.
# If tests are finding unexpected "Product" records, it means
# this file was executed outside of a transaction. Make sure to run
# it only via the console using 'load' command.

puts "\n" + "=" * 80
puts "  BETTERSERVICE - MANUAL TESTING SCRIPT"
puts "=" * 80
puts "  (Running in transaction - all changes will be rolled back)"
puts "=" * 80

# Contatori per il report finale
@tests_passed = 0
@tests_failed = 0
@errors = []

def test(description)
  print "  #{description}... "
  result = yield
  if result
    puts "✓"
    @tests_passed += 1
  else
    puts "✗"
    @tests_failed += 1
    @errors << description
  end
  result
rescue => e
  puts "✗ (ERROR: #{e.message})"
  @tests_failed += 1
  @errors << "#{description} - #{e.message}"
  false
end

def section(name)
  puts "\n" + "-" * 80
  puts "  #{name}"
  puts "-" * 80
end

# Wrap everything in a transaction to keep database clean
ActiveRecord::Base.transaction do
  # ============================================================================
  # SETUP - Preparazione Dati di Test
  # ============================================================================

  section("SETUP - Preparazione Dati di Test")

  user = User.create!(name: "Manual Test User", email: "manual@test.com")
  puts "  ✓ User created: #{user.name} (ID: #{user.id})"

  # ============================================================================
  # TEST 1 - CREATE SERVICE
  # ============================================================================

  section("TEST 1 - Create Service")

  test("create service with valid params succeeds") do
    create_result = Product::CreateService.new(user, params: {
      name: "Console Test Product",
      price: 149.99
    }).call

    if create_result[:success]
      puts "    - Name: #{create_result[:resource].name}"
      puts "    - Price: #{create_result[:resource].price}"
      puts "    - Metadata action: #{create_result[:metadata][:action]}"
      @product_id = create_result[:resource].id
      create_result[:metadata][:action] == :created
    else
      puts "    - Errors: #{create_result[:errors]}"
      false
    end
  end

  test("create service validates params") do
    begin
      Product::CreateService.new(user, params: {
        name: "",
        price: -10
      }).call
      false # Should have raised ValidationError
    rescue BetterService::Errors::Runtime::ValidationError => e
      puts "    - Correctly raised ValidationError: #{e.message}"
      true
    end
  end

  # ============================================================================
  # TEST 2 - INDEX SERVICE
  # ============================================================================

  section("TEST 2 - Index Service")

  Product.create!(name: "Apple Product", price: 99, user: user)
  Product.create!(name: "Samsung Product", price: 89, user: user)

  test("index service lists all products") do
    index_result = Product::IndexService.new(user).call

    if index_result[:success]
      puts "    - Found #{index_result[:items].count} products"
      puts "    - Metadata action: #{index_result[:metadata][:action]}"
      index_result[:items].count >= 3 && index_result[:metadata][:action] == :index
    else
      false
    end
  end

  test("index service filters by search") do
    search_result = Product::IndexService.new(user, params: { search: "Apple" }).call

    if search_result[:success]
      puts "    - Found #{search_result[:items].count} matching products"
      search_result[:items].count == 1 && search_result[:items].first.name.include?("Apple")
    else
      false
    end
  end

  # ============================================================================
  # TEST 3 - SHOW SERVICE
  # ============================================================================

  section("TEST 3 - Show Service")

  test("show service finds product by id") do
    show_result = Product::ShowService.new(user, params: { id: @product_id }).call

    if show_result[:success]
      puts "    - Product: #{show_result[:resource].name}"
      puts "    - Metadata action: #{show_result[:metadata][:action]}"
      show_result[:resource].id == @product_id && show_result[:metadata][:action] == :show
    else
      false
    end
  end

  test("show service fails with invalid id") do
    begin
      Product::ShowService.new(user, params: { id: 99999 }).call
      false # Should have raised ResourceNotFoundError
    rescue BetterService::Errors::Runtime::ResourceNotFoundError => e
      puts "    - Correctly raised ResourceNotFoundError: #{e.message}"
      true
    end
  end

  # ============================================================================
  # TEST 4 - UPDATE SERVICE
  # ============================================================================

  section("TEST 4 - Update Service")

  test("update service modifies product") do
    update_result = Product::UpdateService.new(user, params: {
      id: @product_id,
      price: 199.99
    }).call

    if update_result[:success]
      puts "    - New price: #{update_result[:resource].price}"
      puts "    - Metadata action: #{update_result[:metadata][:action]}"
      update_result[:resource].price.to_f == 199.99 && update_result[:metadata][:action] == :updated
    else
      false
    end
  end

  test("update service validates changes") do
    begin
      Product::UpdateService.new(user, params: {
        id: @product_id,
        price: -50
      }).call
      false # Should have raised DatabaseError (validation)
    rescue BetterService::Errors::Runtime::DatabaseError => e
      puts "    - Correctly raised DatabaseError: #{e.message}"
      true
    end
  end

  # ============================================================================
  # TEST 5 - ACTION SERVICE (Publish)
  # ============================================================================

  section("TEST 5 - Action Service (Publish)")

  test("action service executes custom action") do
    publish_result = Product::PublishService.new(user, params: { id: @product_id }).call

    if publish_result[:success]
      puts "    - Published: #{publish_result[:resource].published}"
      puts "    - Metadata action: #{publish_result[:metadata][:action]}"
      publish_result[:resource].published == true && publish_result[:metadata][:action] == :publish
    else
      false
    end
  end

  # ============================================================================
  # TEST 6 - DESTROY SERVICE
  # ============================================================================

  section("TEST 6 - Destroy Service")

  test("destroy service deletes product") do
    initial_count = Product.count
    destroy_result = Product::DestroyService.new(user, params: { id: @product_id }).call

    if destroy_result[:success]
      puts "    - Metadata action: #{destroy_result[:metadata][:action]}"
      Product.count == initial_count - 1 && destroy_result[:metadata][:action] == :deleted
    else
      false
    end
  end

  # ============================================================================
  # TEST 7 - TRANSACTION SUPPORT
  # ============================================================================

  section("TEST 7 - Transaction Support")

  test("transaction rolls back on validation error") do
    initial_count = Product.count

    begin
      Product::CreateService.new(user, params: {
        name: "",
        price: -10
      }).call
    rescue StandardError
      # Expected to fail
    end

    Product.count == initial_count
  end

  # ============================================================================
  # TEST 8 - AUTHORIZATION (if configured)
  # ============================================================================

  section("TEST 8 - Authorization Support")

  test("service without authorization works normally") do
    # All services work without authorization by default
    result = Product::IndexService.new(user).call
    result[:success]
  end

  # ============================================================================
  # CLEANUP
  # ============================================================================

  section("CLEANUP")
  puts "  Rolling back transaction (database will be clean)..."
  raise ActiveRecord::Rollback
end

# ============================================================================
# FINAL REPORT
# ============================================================================

puts "\n" + "=" * 80
puts "  FINAL REPORT"
puts "=" * 80
puts

total_tests = @tests_passed + @tests_failed
success_rate = total_tests > 0 ? (@tests_passed.to_f / total_tests * 100).round(2) : 0

puts "  Total Tests: #{total_tests}"
puts "  ✓ Passed: #{@tests_passed}"
puts "  ✗ Failed: #{@tests_failed}"
puts "  Success Rate: #{success_rate}%"
puts

if @tests_failed > 0
  puts "  Failed Tests:"
  @errors.each do |error|
    puts "    - #{error}"
  end
  puts
end

if @tests_failed == 0
  puts "  🎉 ALL TESTS PASSED! 🎉"
  puts "  BetterService features verified:"
  puts "    ✓ Create Service (with validation + transaction)"
  puts "    ✓ Index Service (with search)"
  puts "    ✓ Show Service"
  puts "    ✓ Update Service (with transaction)"
  puts "    ✓ Destroy Service (with transaction)"
  puts "    ✓ Action Service (custom publish action)"
  puts "    ✓ Transaction rollback on validation failure"
  puts "    ✓ Metadata with action names"
  puts "    ✓ Authorization support (optional)"
else
  puts "  ⚠️  Some tests failed. Please review the errors above."
end

puts
puts "=" * 80
puts "  DATABASE ROLLED BACK - All test data cleaned up"
puts "=" * 80
puts
