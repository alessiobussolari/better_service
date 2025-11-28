# frozen_string_literal: true

# Manual Test Script for BetterService Repository Pattern
#
# This script runs comprehensive manual tests with real database models
# to verify repository pattern functionality works correctly end-to-end.
#
# Usage:
#   cd test/dummy
#   rails console
#   load '../../manual_repository_test.rb'
#
# All tests run inside database transactions that are automatically rolled back,
# so no data persists after the tests complete.

# Color output helpers
class String
  def colorize(color_code)
    "\e[#{color_code}m#{self}\e[0m"
  end

  def red;    colorize(31) end
  def green;  colorize(32) end
  def yellow; colorize(33) end
  def blue;   colorize(34) end
  def bold;   colorize(1)  end
end

class RepositoryManualTest
  attr_reader :results

  def initialize
    @results = []
    @start_time = Time.current
  end

  def run_all
    puts "\n" + ("=" * 80).blue
    puts "  BetterService Repository Pattern - Manual Test Suite".bold.blue
    puts ("=" * 80).blue + "\n\n"

    # Run all test scenarios
    test_product_repository_crud
    test_user_repository_associations
    test_booking_repository_date_queries
    test_service_with_repository
    test_multiple_repositories_in_service

    # Print summary
    print_summary
  end

  private

  # Test Scenario 1: Product Repository CRUD Operations
  def test_product_repository_crud
    test_name = "Product Repository CRUD Operations"
    puts "\n#{test_name}".bold
    puts "-" * test_name.length

    ActiveRecord::Base.transaction do
      # Setup
      user = User.create!(name: "Test User", email: "test@example.com")
      repo = ProductRepository.new

      # Test 1: Create
      puts "\n  Test 1.1: Create Product".yellow
      result1 = run_test do
        product = repo.create!(name: "Test Product", price: 29.99, user: user)

        assert product.persisted?, "Product should be persisted"
        assert_equal "Test Product", product.name
        assert_equal 29.99.to_d, product.price

        product
      end
      print_test_result("Create Product", result1)

      # Test 2: Find
      puts "\n  Test 1.2: Find Product".yellow
      result2 = run_test do
        product = repo.create!(name: "Find Me", price: 19.99, user: user)
        found = repo.find(product.id)

        assert_equal product.id, found.id
        assert_equal "Find Me", found.name

        found
      end
      print_test_result("Find Product", result2)

      # Test 3: Update
      puts "\n  Test 1.3: Update Product".yellow
      result3 = run_test do
        product = repo.create!(name: "Original", price: 10.00, user: user)
        repo.update(product, name: "Updated", price: 15.00)

        product.reload
        assert_equal "Updated", product.name
        assert_equal 15.00.to_d, product.price

        product
      end
      print_test_result("Update Product", result3)

      # Test 4: Destroy
      puts "\n  Test 1.4: Destroy Product".yellow
      result4 = run_test do
        product = repo.create!(name: "To Delete", price: 5.00, user: user)
        product_id = product.id

        repo.destroy(product)

        assert !Product.exists?(product_id), "Product should be deleted"

        { deleted_id: product_id }
      end
      print_test_result("Destroy Product", result4)

      # Test 5: Search with Pagination
      puts "\n  Test 1.5: Search with Pagination".yellow
      result5 = run_test do
        5.times { |i| repo.create!(name: "Product #{i}", price: (i + 1) * 10, user: user) }

        page1 = repo.search({}, page: 1, per_page: 2)
        page2 = repo.search({}, page: 2, per_page: 2)

        assert_equal 2, page1.to_a.size, "Page 1 should have 2 items"
        assert_equal 2, page2.to_a.size, "Page 2 should have 2 items"

        { page1_count: page1.to_a.size, page2_count: page2.to_a.size }
      end
      print_test_result("Search with Pagination", result5)

      # Test 6: Custom Methods
      puts "\n  Test 1.6: Custom Repository Methods".yellow
      result6 = run_test do
        # Get counts before creating new products
        published_before = repo.published.count
        unpublished_before = repo.unpublished.count

        repo.create!(name: "Published 1", price: 10.00, published: true, user: user)
        repo.create!(name: "Published 2", price: 20.00, published: true, user: user)
        repo.create!(name: "Unpublished", price: 30.00, published: false, user: user)

        published = repo.published
        unpublished = repo.unpublished

        # Check that we have 2 more published and 1 more unpublished
        assert_equal published_before + 2, published.count, "Should have 2 more published"
        assert_equal unpublished_before + 1, unpublished.count, "Should have 1 more unpublished"

        { published_count: published.count, unpublished_count: unpublished.count }
      end
      print_test_result("Custom Repository Methods", result6)

      raise ActiveRecord::Rollback
    end
  end

  # Test Scenario 2: User Repository with Associations
  def test_user_repository_associations
    test_name = "User Repository with Associations"
    puts "\n\n#{test_name}".bold
    puts "-" * test_name.length

    ActiveRecord::Base.transaction do
      repo = UserRepository.new

      # Test 1: Create User with Products
      puts "\n  Test 2.1: User with Eager Loaded Products".yellow
      result1 = run_test do
        user = User.create!(name: "User With Products", email: "products@example.com")
        Product.create!(name: "Product A", price: 10.00, user: user)
        Product.create!(name: "Product B", price: 20.00, user: user)

        loaded_user = repo.with_products.find(user.id)

        assert loaded_user.products.loaded?, "Products should be eager loaded"
        assert_equal 2, loaded_user.products.size

        { user_id: user.id, products_count: loaded_user.products.size }
      end
      print_test_result("Eager Load Products", result1)

      # Test 2: User with Bookings
      puts "\n  Test 2.2: User with Eager Loaded Bookings".yellow
      result2 = run_test do
        user = User.create!(name: "User With Bookings", email: "bookings@example.com")
        Booking.create!(title: "Booking 1", date: Date.current, user: user)
        Booking.create!(title: "Booking 2", date: Date.current + 1.day, user: user)

        loaded_user = repo.with_bookings.find(user.id)

        assert loaded_user.bookings.loaded?, "Bookings should be eager loaded"
        assert_equal 2, loaded_user.bookings.size

        { user_id: user.id, bookings_count: loaded_user.bookings.size }
      end
      print_test_result("Eager Load Bookings", result2)

      # Test 3: Find by Email
      puts "\n  Test 2.3: Find User by Email".yellow
      result3 = run_test do
        user = User.create!(name: "Email User", email: "findme@example.com")

        found = repo.find_by_email("findme@example.com")

        assert_equal user.id, found.id
        assert_equal "Email User", found.name

        { user_id: found.id, email: found.email }
      end
      print_test_result("Find by Email", result3)

      raise ActiveRecord::Rollback
    end
  end

  # Test Scenario 3: Booking Repository Date Queries
  def test_booking_repository_date_queries
    test_name = "Booking Repository Date Queries"
    puts "\n\n#{test_name}".bold
    puts "-" * test_name.length

    ActiveRecord::Base.transaction do
      user = User.create!(name: "Booking User", email: "booking@example.com")
      repo = BookingRepository.new

      # Setup bookings
      Booking.create!(title: "Past Booking", date: Date.current - 7.days, user: user)
      Booking.create!(title: "Today Booking", date: Date.current, user: user)
      Booking.create!(title: "Future Booking", date: Date.current + 7.days, user: user)

      # Test 1: Upcoming Bookings
      puts "\n  Test 3.1: Upcoming Bookings".yellow
      result1 = run_test do
        upcoming = repo.upcoming

        assert_equal 2, upcoming.count, "Should have 2 upcoming (today + future)"
        assert upcoming.all? { |b| b.date >= Date.current }

        { upcoming_count: upcoming.count }
      end
      print_test_result("Upcoming Bookings", result1)

      # Test 2: Past Bookings
      puts "\n  Test 3.2: Past Bookings".yellow
      result2 = run_test do
        past = repo.past

        assert_equal 1, past.count, "Should have 1 past booking"
        assert past.all? { |b| b.date < Date.current }

        { past_count: past.count }
      end
      print_test_result("Past Bookings", result2)

      # Test 3: For Specific Date
      puts "\n  Test 3.3: Bookings for Specific Date".yellow
      result3 = run_test do
        today_bookings = repo.for_date(Date.current)

        assert_equal 1, today_bookings.count
        assert_equal "Today Booking", today_bookings.first.title

        { today_count: today_bookings.count }
      end
      print_test_result("Bookings for Specific Date", result3)

      raise ActiveRecord::Rollback
    end
  end

  # Test Scenario 4: Service with Repository
  def test_service_with_repository
    test_name = "Service with Repository (RepositoryAware)"
    puts "\n\n#{test_name}".bold
    puts "-" * test_name.length

    ActiveRecord::Base.transaction do
      user = User.create!(name: "Service User", email: "service@example.com")

      # Test 1: IndexService with Repository
      puts "\n  Test 4.1: IndexService with Repository".yellow
      result1 = run_test do
        Product.create!(name: "Visible 1", price: 10.00, published: true, user: user)
        Product.create!(name: "Visible 2", price: 20.00, published: true, user: user)
        Product.create!(name: "Hidden", price: 30.00, published: false, user: user)

        service_class = Class.new(BetterService::Services::IndexService) do
          include BetterService::Concerns::Serviceable::RepositoryAware
          repository :product, class_name: "ProductRepository"

          search_with do
            { items: product_repository.published.to_a }
          end
        end

        result = service_class.new(user).call

        assert result[:success], "Service should succeed"
        assert_equal 2, result[:items].size, "Should return 2 published products"

        { success: result[:success], items_count: result[:items].size }
      end
      print_test_result("IndexService with Repository", result1)

      # Test 2: CreateService with Repository
      puts "\n  Test 4.2: CreateService with Repository".yellow
      result2 = run_test do
        service_class = Class.new(BetterService::Services::CreateService) do
          include BetterService::Concerns::Serviceable::RepositoryAware
          repository :product, class_name: "ProductRepository"

          schema do
            required(:name).filled(:string)
            required(:price).filled(:decimal)
          end

          search_with { {} }

          process_with do |_data|
            { resource: product_repository.create!(
              name: params[:name],
              price: params[:price],
              user_id: user.id
            ) }
          end
        end

        result = service_class.new(user, params: { name: "Created via Service", price: 49.99 }).call

        assert result[:success], "Service should succeed"
        assert result[:resource].persisted?, "Product should be persisted"
        assert_equal "Created via Service", result[:resource].name

        { success: result[:success], product_name: result[:resource].name }
      end
      print_test_result("CreateService with Repository", result2)

      raise ActiveRecord::Rollback
    end
  end

  # Test Scenario 5: Multiple Repositories in Service
  def test_multiple_repositories_in_service
    test_name = "Multiple Repositories in Single Service"
    puts "\n\n#{test_name}".bold
    puts "-" * test_name.length

    ActiveRecord::Base.transaction do
      user = User.create!(name: "Multi Repo User", email: "multi@example.com")

      Product.create!(name: "Product 1", price: 10.00, user: user)
      Product.create!(name: "Product 2", price: 20.00, user: user)
      Booking.create!(title: "Booking 1", date: Date.current + 1.day, user: user)
      Booking.create!(title: "Booking 2", date: Date.current + 2.days, user: user)
      Booking.create!(title: "Booking 3", date: Date.current + 3.days, user: user)

      # Test 1: Service with Multiple Repositories
      puts "\n  Test 5.1: Dashboard Service with Multiple Repos".yellow
      result1 = run_test do
        service_class = Class.new(BetterService::Services::IndexService) do
          include BetterService::Concerns::Serviceable::RepositoryAware
          repository :product, class_name: "ProductRepository"
          repository :booking, class_name: "BookingRepository"
          repository :user_repo, class_name: "UserRepository", as: :users

          search_with do
            {
              items: product_repository.all.to_a,
              bookings: booking_repository.upcoming.to_a,
              total_users: users.count
            }
          end

          process_with do |data|
            {
              items: data[:items],
              bookings: data[:bookings],
              metadata: {
                products_count: data[:items].size,
                bookings_count: data[:bookings].size,
                users_count: data[:total_users]
              }
            }
          end
        end

        result = service_class.new(user).call

        assert result[:success], "Service should succeed"
        assert_equal 2, result[:metadata][:products_count]
        assert_equal 3, result[:metadata][:bookings_count]

        {
          success: result[:success],
          products: result[:metadata][:products_count],
          bookings: result[:metadata][:bookings_count],
          users: result[:metadata][:users_count]
        }
      end
      print_test_result("Dashboard with Multiple Repos", result1)

      # Test 2: Repository Memoization
      puts "\n  Test 5.2: Repository Memoization".yellow
      result2 = run_test do
        service_class = Class.new(BetterService::Services::Base) do
          include BetterService::Concerns::Serviceable::RepositoryAware
          repository :product, class_name: "ProductRepository"

          def get_repos
            [product_repository, product_repository, product_repository]
          end
        end

        service = service_class.new(user)
        repos = service.get_repos

        assert repos[0].equal?(repos[1]), "Repos should be same instance"
        assert repos[1].equal?(repos[2]), "Repos should be same instance"

        { memoized: repos[0].equal?(repos[1]) && repos[1].equal?(repos[2]) }
      end
      print_test_result("Repository Memoization", result2)

      raise ActiveRecord::Rollback
    end
  end

  # Helper methods

  def run_test
    yield
    { success: true }
  rescue StandardError => e
    { success: false, error: e }
  end

  def assert(condition, message = "Assertion failed")
    raise message unless condition
  end

  def assert_equal(expected, actual, message = nil)
    msg = message || "Expected #{expected.inspect}, got #{actual.inspect}"
    raise msg unless expected == actual
  end

  def print_test_result(name, result)
    if result[:success]
      puts "    ✓ #{name}".green
      @results << { name: name, success: true }
    else
      puts "    ✗ #{name}".red
      puts "      Error: #{result[:error].message}".red if result[:error]
      puts "      #{result[:error].backtrace.first(3).join("\n      ")}".red if result[:error]
      @results << { name: name, success: false, error: result[:error] }
    end
  end

  def print_summary
    duration = Time.current - @start_time
    passed = @results.count { |r| r[:success] }
    failed = @results.count { |r| !r[:success] }

    puts "\n\n" + ("=" * 80).blue
    puts "  Test Summary".bold.blue
    puts ("=" * 80).blue

    puts "\n  Total Tests: #{@results.count}"
    puts "  Passed: #{passed}".green
    puts "  Failed: #{failed}".send(failed.zero? ? :green : :red)
    puts "  Duration: #{duration.round(2)}s"

    if failed.zero?
      puts "\n  All tests passed! ✓".green.bold
    else
      puts "\n  Some tests failed! ✗".red.bold
      puts "\n  Failed tests:"
      @results.select { |r| !r[:success] }.each do |result|
        puts "    - #{result[:name]}".red
        puts "      #{result[:error].message}".red if result[:error]
      end
    end

    puts "\n" + ("=" * 80).blue + "\n\n"
  end
end

# Run the tests
puts "\nStarting BetterService Repository Pattern Manual Tests..."
puts "Note: All tests run in transactions and will be rolled back.\n"

tester = RepositoryManualTest.new
tester.run_all

puts "Manual tests completed. Database has been rolled back to original state.\n"
