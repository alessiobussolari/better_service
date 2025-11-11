# frozen_string_literal: true

require "test_helper"

class AuthorizableTest < ActiveSupport::TestCase
  # Test service WITH authorization
  class AuthorizedService < BetterService::Services::Base
    self._allow_nil_user = true

    schema do
      required(:action).filled(:string)
    end

    authorize_with do
      user&.admin? == true
    end

    search_with do
      { data: "searched" }
    end

    process_with do |data|
      { result: "processed", data: data }
    end

    respond_with do |data|
      success_result("Success", data)
    end
  end

  # Test service WITHOUT authorization (should work normally)
  class UnauthorizedService < BetterService::Services::Base
    self._allow_nil_user = true

    schema do
      required(:action).filled(:string)
    end

    search_with do
      { data: "searched" }
    end

    process_with do |data|
      { result: "processed" }
    end

    respond_with do |data|
      success_result("Success", data)
    end
  end

  # Test service with authorization that uses params
  class ParamsBasedAuthService < BetterService::Services::Base
    schema do
      required(:user_id).filled(:integer)
    end

    authorize_with do
      params[:user_id] == user&.id
    end

    search_with do
      { data: "searched" }
    end

    process_with do |data|
      { result: "authorized user" }
    end

    respond_with do |data|
      success_result("Success", data)
    end
  end

  # Test service with authorization that checks resource ownership
  class ResourceOwnershipService < BetterService::Services::Base
    schema do
      required(:id).filled(:integer)
    end

    authorize_with do
      # Simulate loading resource for authorization check
      @resource = { id: params[:id], owner_id: 1 }
      @resource[:owner_id] == user&.id
    end

    search_with do
      # Reuse cached resource from authorization
      { resource: @resource }
    end

    process_with do |data|
      { result: "owner verified", resource: data[:resource] }
    end

    respond_with do |data|
      success_result("Success", data)
    end
  end

  # Mock user class
  class MockUser
    attr_accessor :id, :admin

    def initialize(id:, admin: false)
      @id = id
      @admin = admin
    end

    def admin?
      @admin
    end
  end

  # Test 1: Authorization passes - service continues normally
  test "authorization passes when block returns true" do
    admin_user = MockUser.new(id: 1, admin: true)
    result = AuthorizedService.new(admin_user, params: { action: "test" }).call

    assert result[:success]
    assert_equal "processed", result[:result]
  end

  # Test 2: Authorization fails - raises AuthorizationError
  test "authorization fails when block returns false" do
    non_admin_user = MockUser.new(id: 2, admin: false)

    error = assert_raises(BetterService::Errors::Runtime::AuthorizationError) do
      AuthorizedService.new(non_admin_user, params: { action: "test" }).call
    end

    assert_equal :unauthorized, error.code
    assert_match(/not authorized/i, error.message)
  end

  # Test 3: Authorization fails with nil user
  test "authorization fails when user is nil" do
    error = assert_raises(BetterService::Errors::Runtime::AuthorizationError) do
      AuthorizedService.new(nil, params: { action: "test" }).call
    end

    assert_equal :unauthorized, error.code
    assert_match(/not authorized/i, error.message)
  end

  # Test 4: Service without authorization works normally
  test "service without authorization block works normally" do
    result = UnauthorizedService.new(nil, params: { action: "test" }).call

    assert result[:success]
    assert_equal "processed", result[:result]
  end

  # Test 5: Authorization has access to params
  test "authorization block has access to params" do
    user = MockUser.new(id: 42, admin: false)

    # Should pass because params[:user_id] matches user.id
    result = ParamsBasedAuthService.new(user, params: { user_id: 42 }).call
    assert result[:success]

    # Should fail because params[:user_id] doesn't match
    error = assert_raises(BetterService::Errors::Runtime::AuthorizationError) do
      ParamsBasedAuthService.new(user, params: { user_id: 99 }).call
    end
    assert_equal :unauthorized, error.code
  end

  # Test 6: Authorization has access to user
  test "authorization block has access to user object" do
    user = MockUser.new(id: 1, admin: true)
    result = AuthorizedService.new(user, params: { action: "test" }).call

    assert result[:success], "Should pass when user.admin? is true"
  end

  # Test 7: Authorization can load and cache resources
  test "authorization can load resources that are reused in search" do
    user = MockUser.new(id: 1, admin: false)
    result = ResourceOwnershipService.new(user, params: { id: 123 }).call

    assert result[:success]
    assert_equal "owner verified", result[:result]
    # Verify resource was passed through from authorization to search
    assert_equal 123, result[:resource][:id]
  end

  # Test 8: Authorization fails before search is executed
  test "authorization failure prevents search from executing" do
    search_executed = false

    service_class = Class.new(BetterService::Services::Base) do
      self._allow_nil_user = true

      schema { required(:action).filled(:string) }

      authorize_with do
        false  # Always fail
      end

      search_with do
        search_executed = true
        { data: "should not execute" }
      end

      process_with do |data|
        { result: "should not execute" }
      end

      respond_with do |data|
        success_result("Success", data)
      end
    end

    error = assert_raises(BetterService::Errors::Runtime::AuthorizationError) do
      service_class.new(nil, params: { action: "test" }).call
    end

    assert_equal :unauthorized, error.code
    assert_not search_executed, "Search should not execute when authorization fails"
  end

  # Test 9: Authorization with Pundit-style policy
  test "authorization integrates with Pundit-style policies" do
    # Mock Pundit policy
    policy_class = Class.new do
      def initialize(user, record)
        @user = user
        @record = record
      end

      def update?
        @user&.admin? == true
      end
    end

    service_class = Class.new(BetterService::Services::Base) do
      schema { required(:id).filled(:integer) }

      authorize_with do
        resource = { id: params[:id] }
        policy_class.new(user, resource).update?
      end

      search_with { { resource: "found" } }
      process_with { |data| { result: "updated" } }

      # Make policy_class available to the block
      define_method(:policy_class) { policy_class }
    end

    admin_user = MockUser.new(id: 1, admin: true)
    result = service_class.new(admin_user, params: { id: 123 }).call
    assert result[:success]

    non_admin = MockUser.new(id: 2, admin: false)
    error = assert_raises(BetterService::Errors::Runtime::AuthorizationError) do
      service_class.new(non_admin, params: { id: 123 }).call
    end
    assert_equal :unauthorized, error.code
  end

  # Test 10: Authorization with CanCanCan-style ability
  test "authorization integrates with CanCanCan-style abilities" do
    # Mock CanCanCan Ability
    ability_class = Class.new do
      def initialize(user)
        @user = user
      end

      def can?(action, subject)
        @user&.admin? == true && action == :destroy
      end
    end

    service_class = Class.new(BetterService::Services::Base) do
      schema { required(:id).filled(:integer) }

      authorize_with do
        ability_class.new(user).can?(:destroy, :product)
      end

      search_with { { resource: "found" } }
      process_with { |data| { result: "destroyed" } }

      define_method(:ability_class) { ability_class }
    end

    admin_user = MockUser.new(id: 1, admin: true)
    result = service_class.new(admin_user, params: { id: 123 }).call
    assert result[:success]

    non_admin = MockUser.new(id: 2, admin: false)
    error = assert_raises(BetterService::Errors::Runtime::AuthorizationError) do
      service_class.new(non_admin, params: { id: 123 }).call
    end
    assert_equal :unauthorized, error.code
  end

  # Test 11: Authorization with custom logic
  test "authorization with completely custom logic" do
    service_class = Class.new(BetterService::Services::Base) do
      schema { required(:secret_key).filled(:string) }

      authorize_with do
        # Custom logic: check secret key matches expected value
        params[:secret_key] == "super-secret-123" && user&.id&.positive?
      end

      search_with { { data: "secure data" } }
      process_with { |data| { result: "access granted" } }
    end

    user = MockUser.new(id: 1)

    # Should pass with correct secret
    result = service_class.new(user, params: { secret_key: "super-secret-123" }).call
    assert result[:success]

    # Should fail with wrong secret
    error = assert_raises(BetterService::Errors::Runtime::AuthorizationError) do
      service_class.new(user, params: { secret_key: "wrong" }).call
    end
    assert_equal :unauthorized, error.code
  end

  # Test 12: Authorization works with all service types
  test "authorization works with CreateService" do
    service_class = Class.new(BetterService::Services::CreateService) do
      schema { required(:name).filled(:string) }

      authorize_with do
        user&.admin? == true
      end

      search_with { {} }
      process_with { |data| { resource: { name: params[:name] } } }
    end

    admin = MockUser.new(id: 1, admin: true)
    result = service_class.new(admin, params: { name: "Test" }).call
    assert result[:success]
    assert_equal :created, result[:metadata][:action]

    non_admin = MockUser.new(id: 2, admin: false)
    error = assert_raises(BetterService::Errors::Runtime::AuthorizationError) do
      service_class.new(non_admin, params: { name: "Test" }).call
    end
    assert_equal :unauthorized, error.code
  end

  test "authorization works with UpdateService" do
    service_class = Class.new(BetterService::Services::UpdateService) do
      schema { required(:id).filled(:integer) }

      authorize_with do
        user&.admin? == true
      end

      search_with { { resource: { id: params[:id] } } }
      process_with { |data| { resource: data[:resource] } }
    end

    admin = MockUser.new(id: 1, admin: true)
    result = service_class.new(admin, params: { id: 1 }).call
    assert result[:success]
    assert_equal :updated, result[:metadata][:action]
  end

  test "authorization works with ActionService" do
    service_class = Class.new(BetterService::Services::ActionService) do
      action_name :publish
      schema { required(:id).filled(:integer) }

      authorize_with do
        user&.admin? == true
      end

      search_with { { resource: { id: params[:id] } } }
      process_with { |data| { resource: data[:resource] } }
    end

    admin = MockUser.new(id: 1, admin: true)
    result = service_class.new(admin, params: { id: 1 }).call
    assert result[:success]
    assert_equal :publish, result[:metadata][:action]
  end
end
