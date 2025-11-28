# frozen_string_literal: true

require "test_helper"

class RepositoryIntegrationTest < ActiveSupport::TestCase
  # ========================================
  # Setup and Teardown
  # ========================================

  def setup
    @user = User.create!(name: "Test User", email: "test@example.com")
    @user2 = User.create!(name: "Other User", email: "other@example.com")

    @product1 = Product.create!(name: "Product 1", price: 10.00, published: true, user: @user)
    @product2 = Product.create!(name: "Product 2", price: 20.00, published: false, user: @user)
    @product3 = Product.create!(name: "Product 3", price: 30.00, published: true, user: @user2)

    @booking1 = Booking.create!(title: "Past Booking", date: Date.current - 7.days, user: @user)
    @booking2 = Booking.create!(title: "Today Booking", date: Date.current, user: @user)
    @booking3 = Booking.create!(title: "Future Booking", date: Date.current + 7.days, user: @user2)

    @product_repo = ProductRepository.new
    @user_repo = UserRepository.new
    @booking_repo = BookingRepository.new
  end

  def teardown
    Booking.delete_all
    Product.delete_all
    User.delete_all
  end

  # ========================================
  # Group 1: BaseRepository with Real Models
  # ========================================

  test "find retrieves existing record" do
    result = @product_repo.find(@product1.id)

    assert_equal @product1.id, result.id
    assert_equal "Product 1", result.name
  end

  test "find raises RecordNotFound for missing id" do
    assert_raises(ActiveRecord::RecordNotFound) do
      @product_repo.find(999_999)
    end
  end

  test "find_by returns matching record" do
    result = @product_repo.find_by(name: "Product 2")

    assert_not_nil result
    assert_equal @product2.id, result.id
  end

  test "find_by returns nil when no match" do
    result = @product_repo.find_by(name: "Non-existent")

    assert_nil result
  end

  test "where returns filtered results" do
    results = @product_repo.where(published: true).to_a

    assert_equal 2, results.size
    assert results.all?(&:published)
  end

  test "all returns all records" do
    results = @product_repo.all.to_a

    assert_equal 3, results.size
  end

  test "count returns correct count" do
    assert_equal 3, @product_repo.count
    assert_equal 2, @user_repo.count
    assert_equal 3, @booking_repo.count
  end

  test "exists? returns true for matching condition" do
    assert @product_repo.exists?(name: "Product 1")
    refute @product_repo.exists?(name: "Non-existent")
  end

  # ========================================
  # Group 2: CRUD Operations
  # ========================================

  test "build creates unsaved instance" do
    product = @product_repo.build(name: "New Product", price: 15.00, user: @user)

    assert_kind_of Product, product
    assert_equal "New Product", product.name
    refute product.persisted?
  end

  test "create persists new record to database" do
    initial_count = Product.count

    product = @product_repo.create(name: "Created Product", price: 25.00, user: @user)

    assert_kind_of Product, product
    assert product.persisted?
    assert_equal initial_count + 1, Product.count
  end

  test "create! raises on validation failure" do
    assert_raises(ActiveRecord::RecordInvalid) do
      @product_repo.create!(name: nil, price: 10.00, user: @user)
    end
  end

  test "create! succeeds with valid attributes" do
    product = @product_repo.create!(name: "Valid Product", price: 50.00, user: @user)

    assert_kind_of Product, product
    assert product.persisted?
  end

  test "update modifies existing record by instance" do
    @product_repo.update(@product1, name: "Updated Name")

    @product1.reload
    assert_equal "Updated Name", @product1.name
  end

  test "update modifies existing record by id" do
    @product_repo.update(@product1.id, name: "Updated By ID")

    @product1.reload
    assert_equal "Updated By ID", @product1.name
  end

  test "destroy removes record from database" do
    initial_count = Product.count

    @product_repo.destroy(@product1)

    assert_equal initial_count - 1, Product.count
    refute Product.exists?(@product1.id)
  end

  test "destroy removes record by id" do
    initial_count = Product.count

    @product_repo.destroy(@product2.id)

    assert_equal initial_count - 1, Product.count
    refute Product.exists?(@product2.id)
  end

  test "delete removes record without callbacks" do
    initial_count = Product.count

    @product_repo.delete(@product1.id)

    assert_equal initial_count - 1, Product.count
  end

  # ========================================
  # Group 3: Search with Pagination
  # ========================================

  test "search returns all records with empty predicates" do
    results = @product_repo.search({})

    assert results.respond_to?(:to_a)
    assert_equal 3, results.to_a.size
  end

  test "search with pagination returns correct page" do
    results = @product_repo.search({}, page: 1, per_page: 2)

    assert_equal 2, results.to_a.size
  end

  test "search with page 2 returns remaining records" do
    results = @product_repo.search({}, page: 2, per_page: 2)

    assert_equal 1, results.to_a.size
  end

  test "search with limit returns limited results" do
    results = @product_repo.search({}, limit: 2)

    assert_equal 2, results.to_a.size
  end

  test "search with limit 1 returns single record" do
    result = @product_repo.search({}, limit: 1)

    assert_kind_of Product, result
  end

  test "search with limit nil returns all without pagination" do
    results = @product_repo.search({}, limit: nil)

    assert_equal 3, results.to_a.size
  end

  test "search with includes eager loads associations" do
    results = @user_repo.search({}, includes: [:products])

    assert results.respond_to?(:to_a)
    # Verifying eager loading worked - no additional queries needed
    assert_not_empty results.first.products
  end

  test "search with order sorts results" do
    results = @product_repo.search({}, order: "price DESC")

    prices = results.to_a.map(&:price)
    assert_equal prices.sort.reverse, prices
  end

  test "search with order ASC sorts ascending" do
    results = @product_repo.search({}, order: "price ASC")

    prices = results.to_a.map(&:price)
    assert_equal prices.sort, prices
  end

  # ========================================
  # Group 4: Custom Repository Methods
  # ========================================

  test "ProductRepository.published returns only published products" do
    results = @product_repo.published

    assert_equal 2, results.count
    assert results.all?(&:published)
  end

  test "ProductRepository.unpublished returns only unpublished products" do
    results = @product_repo.unpublished

    assert_equal 1, results.count
    assert results.none?(&:published)
  end

  test "ProductRepository.by_user filters by user_id" do
    results = @product_repo.by_user(@user.id)

    assert_equal 2, results.count
    assert results.all? { |p| p.user_id == @user.id }
  end

  test "ProductRepository.in_price_range filters by price range" do
    results = @product_repo.in_price_range(15.00, 25.00)

    assert_equal 1, results.count
    assert_equal @product2.id, results.first.id
  end

  test "UserRepository.with_products eager loads products" do
    results = @user_repo.with_products

    user = results.find(@user.id)
    assert user.products.loaded?
  end

  test "UserRepository.with_bookings eager loads bookings" do
    results = @user_repo.with_bookings

    user = results.find(@user.id)
    assert user.bookings.loaded?
  end

  test "UserRepository.with_all_associations eager loads all" do
    results = @user_repo.with_all_associations

    user = results.find(@user.id)
    assert user.products.loaded?
    assert user.bookings.loaded?
  end

  test "UserRepository.find_by_email finds user" do
    result = @user_repo.find_by_email("test@example.com")

    assert_equal @user.id, result.id
  end

  test "BookingRepository.upcoming returns future bookings" do
    results = @booking_repo.upcoming

    assert_equal 2, results.count
    assert results.all? { |b| b.date >= Date.current }
  end

  test "BookingRepository.past returns past bookings" do
    results = @booking_repo.past

    assert_equal 1, results.count
    assert results.all? { |b| b.date < Date.current }
  end

  test "BookingRepository.by_user filters by user_id" do
    results = @booking_repo.by_user(@user.id)

    assert_equal 2, results.count
    assert results.all? { |b| b.user_id == @user.id }
  end

  test "BookingRepository.for_date finds bookings on specific date" do
    results = @booking_repo.for_date(Date.current)

    assert_equal 1, results.count
    assert_equal @booking2.id, results.first.id
  end

  # ========================================
  # Group 5: RepositoryAware Integration
  # ========================================

  test "service with repository creates record via repository" do
    service_class = Class.new(BetterService::Services::Base) do
      include BetterService::Concerns::Serviceable::RepositoryAware
      repository :product, class_name: "ProductRepository"

      performed_action :created
      with_transaction true

      schema do
        required(:name).filled(:string)
        required(:price).filled(:decimal)
        required(:user_id).filled(:integer)
      end

      search_with do
        {}
      end

      process_with do |_data|
        { resource: product_repository.create!(
          name: params[:name],
          price: params[:price],
          user_id: params[:user_id]
        ) }
      end
    end

    service = service_class.new(@user, params: { name: "Service Created", price: 99.99, user_id: @user.id })
    result = service.call

    assert result[:success]
    assert_kind_of Product, result[:resource]
    assert_equal "Service Created", result[:resource].name
    assert result[:resource].persisted?
  end

  test "service with repository performs search via repository" do
    service_class = Class.new(BetterService::Services::Base) do
      include BetterService::Concerns::Serviceable::RepositoryAware
      repository :product, class_name: "ProductRepository"

      performed_action :listed

      search_with do
        { items: product_repository.published.to_a }
      end
    end

    service = service_class.new(@user)
    result = service.call

    assert result[:success]
    assert_equal 2, result[:items].size
    assert result[:items].all?(&:published)
  end

  test "service with multiple repositories works correctly" do
    service_class = Class.new(BetterService::Services::Base) do
      include BetterService::Concerns::Serviceable::RepositoryAware
      repository :product, class_name: "ProductRepository"
      repository :booking, class_name: "BookingRepository"

      performed_action :listed

      search_with do
        {
          items: product_repository.all.to_a,
          bookings: booking_repository.upcoming.to_a
        }
      end

      process_with do |data|
        {
          items: data[:items],
          bookings: data[:bookings],
          metadata: {
            product_count: data[:items].size,
            booking_count: data[:bookings].size
          }
        }
      end
    end

    service = service_class.new(@user)
    result = service.call

    assert result[:success]
    assert_equal 3, result[:metadata][:product_count]
    assert_equal 2, result[:metadata][:booking_count]
  end

  test "repository is memoized within service" do
    service_class = Class.new(BetterService::Services::Base) do
      include BetterService::Concerns::Serviceable::RepositoryAware
      repository :product, class_name: "ProductRepository"

      def repository_instances
        [product_repository, product_repository, product_repository]
      end
    end

    service = service_class.new(@user)
    repos = service.repository_instances

    assert_same repos[0], repos[1]
    assert_same repos[1], repos[2]
  end
end
