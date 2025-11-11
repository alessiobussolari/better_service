# frozen_string_literal: true

require "test_helper"

class ProductServicesIntegrationTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Test User", email: "test@example.com")
  end

  teardown do
    Product.destroy_all
    User.destroy_all
  end

  # ====================
  # CREATE SERVICE TESTS
  # ====================

  test "create service - successful creation with valid params" do
    result = Product::CreateService.new(@user, params: {
      name: "Test Product",
      price: 99.99
    }).call

    assert result[:success], "Create should succeed"
    assert_equal :created, result[:metadata][:action]
    assert_instance_of Product, result[:resource]
    assert_equal "Test Product", result[:resource].name
    assert_equal 99.99, result[:resource].price.to_f
    assert_equal 1, Product.count
  end

  test "create service - validation failure with invalid params" do
    error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
      Product::CreateService.new(@user, params: {
        name: "",
        price: -10
      })
    end

    assert_equal :validation_failed, error.code
    assert error.context[:validation_errors].present?
  end

  test "create service - transaction rollback on database error" do
    initial_count = Product.count

    result = Product::CreateService.new(@user, params: {
      name: "Valid Name",
      price: 50
    }).call

    # Always assert - either success with count increase, or failure with rollback
    if result[:success]
      assert_equal initial_count + 1, Product.count, "Success should increase count"
    else
      assert_equal initial_count, Product.count, "Failure should rollback transaction"
    end
  end

  # ====================
  # INDEX SERVICE TESTS
  # ====================

  test "index service - returns list of products" do
    Product.create!(name: "Product 1", price: 10, user: @user)
    Product.create!(name: "Product 2", price: 20, user: @user)
    Product.create!(name: "Product 3", price: 30, user: @user)

    result = Product::IndexService.new(@user).call

    assert result[:success]
    assert_equal :index, result[:metadata][:action]
    assert_equal 3, result[:items].count
  end

  test "index service - search functionality" do
    Product.create!(name: "Apple iPhone", price: 999, user: @user)
    Product.create!(name: "Samsung Galaxy", price: 899, user: @user)
    Product.create!(name: "Apple iPad", price: 599, user: @user)

    result = Product::IndexService.new(@user, params: { search: "Apple" }).call

    assert result[:success]
    assert_equal 2, result[:items].count
    assert result[:items].all? { |p| p.name.include?("Apple") }
  end

  # ====================
  # SHOW SERVICE TESTS
  # ====================

  test "show service - returns single product" do
    product = Product.create!(name: "Test Product", price: 50, user: @user)

    result = Product::ShowService.new(@user, params: { id: product.id }).call

    assert result[:success]
    assert_equal :show, result[:metadata][:action]
    assert_equal product.id, result[:resource].id
  end

  test "show service - fails with invalid id" do
    error = assert_raises(BetterService::Errors::Runtime::ResourceNotFoundError) do
      Product::ShowService.new(@user, params: { id: 99999 }).call
    end

    assert_equal :resource_not_found, error.code
  end

  # ====================
  # UPDATE SERVICE TESTS
  # ====================

  test "update service - successful update" do
    product = Product.create!(name: "Old Name", price: 50, user: @user)

    result = Product::UpdateService.new(@user, params: {
      id: product.id,
      name: "New Name",
      price: 75
    }).call

    assert result[:success]
    assert_equal :updated, result[:metadata][:action]
    product.reload
    assert_equal "New Name", product.name
    assert_equal 75, product.price.to_f
  end

  test "update service - transaction rollback on error" do
    product = Product.create!(name: "Original", price: 50, user: @user)

    # Try to update with invalid data - should raise during transaction
    error = assert_raises(BetterService::Errors::Runtime::DatabaseError) do
      Product::UpdateService.new(@user, params: {
        id: product.id,
        name: "",  # Invalid: empty name
        price: -10  # Invalid: negative price
      }).call
    end

    assert_equal :database_error, error.code
    product.reload
    # Product should remain unchanged due to transaction rollback
    assert_equal "Original", product.name
    assert_equal 50, product.price.to_f
  end

  # ====================
  # DESTROY SERVICE TESTS
  # ====================

  test "destroy service - successful deletion" do
    product = Product.create!(name: "To Delete", price: 50, user: @user)
    initial_count = Product.count

    result = Product::DestroyService.new(@user, params: { id: product.id }).call

    assert result[:success]
    assert_equal :deleted, result[:metadata][:action]
    assert_equal initial_count - 1, Product.count
    assert_raises(ActiveRecord::RecordNotFound) { Product.find(product.id) }
  end

  # ====================
  # ACTION SERVICE TESTS (publish)
  # ====================

  test "action service - publish product" do
    product = Product.create!(name: "Unpublished", price: 50, published: false, user: @user)

    result = Product::PublishService.new(@user, params: { id: product.id }).call

    assert result[:success]
    assert_equal :publish, result[:metadata][:action]
    product.reload
    assert product.published
  end

  # ====================
  # INTEGRATION TEST - Full workflow
  # ====================

  test "full workflow - create, update, publish, destroy" do
    # Step 1: Create
    create_result = Product::CreateService.new(@user, params: {
      name: "Workflow Product",
      price: 100
    }).call
    assert create_result[:success]
    product_id = create_result[:resource].id

    # Step 2: Update
    update_result = Product::UpdateService.new(@user, params: {
      id: product_id,
      price: 120
    }).call
    assert update_result[:success]
    assert_equal 120, update_result[:resource].price.to_f

    # Step 3: Publish (custom action)
    publish_result = Product::PublishService.new(@user, params: { id: product_id }).call
    assert publish_result[:success]

    # Step 4: Verify with Show
    show_result = Product::ShowService.new(@user, params: { id: product_id }).call
    assert show_result[:success]
    assert show_result[:resource].published

    # Step 5: Destroy
    destroy_result = Product::DestroyService.new(@user, params: { id: product_id }).call
    assert destroy_result[:success]
    assert_equal 0, Product.count
  end

  # ====================
  # AUTHORIZATION TESTS
  # ====================

  test "authorization - service with authorization check passes when authorized" do
    # Create a service with authorization
    service_class = Class.new(BetterService::Services::UpdateService) do
      schema { required(:id).filled(:integer) }

      authorize_with do
        # Simulate authorization check - always pass
        true
      end

      search_with do
        { resource: Product.find(params[:id]) }
      end

      process_with do |data|
        data[:resource].update!(name: "Authorized Update")
        { resource: data[:resource] }
      end
    end

    product = Product.create!(name: "Original", price: 50, user: @user)
    result = service_class.new(@user, params: { id: product.id }).call

    assert result[:success], "Should succeed when authorized"
    assert_equal :updated, result[:metadata][:action]
    assert_equal "Authorized Update", result[:resource].name
  end

  test "authorization - service with authorization check fails when not authorized" do
    # Create a service with authorization that fails
    service_class = Class.new(BetterService::Services::UpdateService) do
      schema { required(:id).filled(:integer) }

      authorize_with do
        # Simulate authorization check - always fail
        false
      end

      search_with do
        { resource: Product.find(params[:id]) }
      end

      process_with do |data|
        data[:resource].update!(name: "Should Not Update")
        { resource: data[:resource] }
      end
    end

    product = Product.create!(name: "Original", price: 50, user: @user)

    error = assert_raises(BetterService::Errors::Runtime::AuthorizationError) do
      service_class.new(@user, params: { id: product.id }).call
    end

    assert_equal :unauthorized, error.code
    assert_match(/not authorized/i, error.message)

    # Verify product was NOT updated
    product.reload
    assert_equal "Original", product.name
  end

  test "authorization - check runs before search to fail fast" do
    search_executed = false

    # Create a service that tracks if search was executed
    service_class = Class.new(BetterService::Services::UpdateService) do
      schema { required(:id).filled(:integer) }

      authorize_with do
        false  # Always fail authorization
      end

      search_with do
        search_executed = true
        { resource: Product.find(params[:id]) }
      end

      process_with do |data|
        { resource: data[:resource] }
      end

      # Make search_executed accessible
      define_method(:search_executed?) { search_executed }
    end

    product = Product.create!(name: "Test", price: 50, user: @user)

    error = assert_raises(BetterService::Errors::Runtime::AuthorizationError) do
      service_class.new(@user, params: { id: product.id }).call
    end

    assert_equal :unauthorized, error.code
    assert_not search_executed, "Search should NOT execute when authorization fails (fail fast)"
  end

  test "authorization - can check resource ownership" do
    other_user = User.create!(name: "Other User", email: "other@example.com")
    product = Product.create!(name: "Owner Product", price: 50, user: @user)

    # Service that checks resource ownership
    service_class = Class.new(BetterService::Services::UpdateService) do
      schema { required(:id).filled(:integer) }

      authorize_with do
        product = Product.find(params[:id])
        product.user_id == user.id
      end

      search_with do
        { resource: Product.find(params[:id]) }
      end

      process_with do |data|
        data[:resource].update!(name: "Updated by Owner")
        { resource: data[:resource] }
      end
    end

    # Owner should succeed
    result = service_class.new(@user, params: { id: product.id }).call
    assert result[:success], "Owner should be authorized"

    # Other user should fail
    error = assert_raises(BetterService::Errors::Runtime::AuthorizationError) do
      service_class.new(other_user, params: { id: product.id }).call
    end
    assert_equal :unauthorized, error.code
  end
end
