# frozen_string_literal: true

require "test_helper"

module BetterService
  class BaseTest < ActiveSupport::TestCase
    # Dummy user class for testing
    class DummyUser
      attr_accessor :id, :name

      def initialize(id: 1, name: "Test User")
        @id = id
        @name = name
      end
    end

    def setup
      @user = DummyUser.new
      @params = { page: 1, search: "test" }
    end

    # ========================================
    # Initialize Tests
    # ========================================

    test "initialize requires schema to be defined" do
      service_class = Class.new(Base)
      # Remove schema from class (simulating no schema defined)
      service_class._schema = nil

      error = assert_raises(SchemaRequiredError) do
        service_class.new(@user, params: {})
      end

      assert_match(/must define a schema block/, error.message)
      assert_match(/Add 'schema do ... end'/, error.message)
    end

    test "initialize requires user by default" do
      error = assert_raises(ArgumentError) do
        Base.new(nil, params: {})
      end

      assert_match(/User cannot be nil/, error.message)
      assert_match(/allow_nil_user/, error.message)
    end

    test "initialize accepts user and params" do
      service = Base.new(@user, params: @params)

      assert_equal @user, service.instance_variable_get(:@user)
      assert_kind_of Hash, service.instance_variable_get(:@params)
    end

    test "initialize sanitizes ActionController::Parameters to hash with symbol keys" do
      # Simulate ActionController::Parameters
      ac_params = ActionController::Parameters.new(page: "1", search: "test", controller: "bookings")

      service = Base.new(@user, params: ac_params)
      params = service.instance_variable_get(:@params)

      assert_kind_of Hash, params
      assert params.key?(:page)
      assert params.key?(:search)
      refute params.key?("page"), "Should not have string keys"
    end

    test "initialize converts plain hash params to symbol keys" do
      plain_hash = { "page" => 1, "search" => "test" }

      service = Base.new(@user, params: plain_hash)
      params = service.instance_variable_get(:@params)

      assert params.key?(:page)
      assert params.key?(:search)
      refute params.key?("page")
    end

    test "initialize handles nil params gracefully" do
      service = Base.new(@user, params: nil)
      params = service.instance_variable_get(:@params)

      assert_equal({}, params)
    end

    test "initialize handles empty params" do
      service = Base.new(@user, params: {})
      params = service.instance_variable_get(:@params)

      assert_equal({}, params)
    end

    # ========================================
    # Result Helpers Tests
    # ========================================

    test "success_result returns hash with success true" do
      service = Base.new(@user)
      result = service.send(:success_result, "Operation successful")

      assert result[:success]
      assert_equal "Operation successful", result[:message]
    end

    test "success_result merges additional data" do
      service = Base.new(@user)
      result = service.send(:success_result, "Done", { items: [1, 2, 3], count: 3 })

      assert result[:success]
      assert_equal "Done", result[:message]
      assert_equal [1, 2, 3], result[:items]
      assert_equal 3, result[:count]
    end

    test "failure_result returns hash with success false" do
      service = Base.new(@user)
      result = service.send(:failure_result, "Operation failed")

      refute result[:success]
      assert_equal "Operation failed", result[:error]
    end

    test "failure_result includes errors hash" do
      service = Base.new(@user)
      errors = { name: "can't be blank", email: "is invalid" }
      result = service.send(:failure_result, "Validation failed", errors)

      refute result[:success]
      assert_equal "Validation failed", result[:error]
      assert_equal errors, result[:errors]
    end

    test "failure_result handles empty errors" do
      service = Base.new(@user)
      result = service.send(:failure_result, "Something went wrong")

      refute result[:success]
      assert_equal "Something went wrong", result[:error]
      assert_equal({}, result[:errors])
    end

    test "success_result includes metadata with action when action_name is set" do
      service_class = Class.new(Base) do
        self._action_name = :test_action
      end
      service = service_class.new(@user)
      result = service.send(:success_result, "Success", { data: "value" })

      assert result[:success]
      assert_equal "Success", result[:message]
      assert_equal "value", result[:data]
      assert result.key?(:metadata)
      assert_equal :test_action, result[:metadata][:action]
    end

    test "success_result includes empty metadata when action_name is not set" do
      service = Base.new(@user)
      result = service.send(:success_result, "Success", { data: "value" })

      assert result[:success]
      assert_equal "Success", result[:message]
      assert_equal "value", result[:data]
      assert result.key?(:metadata)
      assert_equal({}, result[:metadata])
    end

    test "success_result merges additional metadata if provided" do
      service_class = Class.new(Base) do
        self._action_name = :test_action
      end
      service = service_class.new(@user)
      result = service.send(:success_result, "Success", {
        data: "value",
        metadata: { stats: { count: 10 } }
      })

      assert result[:success]
      assert_equal "Success", result[:message]
      assert_equal "value", result[:data]
      assert result.key?(:metadata)
      assert_equal :test_action, result[:metadata][:action]
      assert_equal 10, result[:metadata][:stats][:count]
    end

    # ========================================
    # 4-Phase Execution Flow Tests
    # ========================================

    # Test service that tracks phase execution
    class TestService < Base
      attr_reader :phases_executed

      def initialize(user, params: {})
        super
        @phases_executed = []
      end

      def search
        @phases_executed << :search
        { raw_data: "from_db" }
      end

      def process(data)
        @phases_executed << :process
        { processed: data[:raw_data].upcase }
      end

      def transform(data)
        @phases_executed << :transform
        { transformed: "#{data[:processed]}!" }
      end

      def respond(data)
        @phases_executed << :respond
        success_result("All phases completed", data)
      end
    end

    test "call method exists and returns hash" do
      service = Base.new(@user)
      result = service.call

      assert_kind_of Hash, result
      assert result.key?(:success)
    end

    test "call executes all phases in order" do
      service = TestService.new(@user)
      service.call

      assert_equal [:search, :process, :transform, :respond], service.phases_executed
    end

    test "call passes data through phases correctly" do
      service = TestService.new(@user)
      result = service.call

      assert result[:success]
      assert_equal "FROM_DB!", result[:transformed]
    end

    test "call returns success when all phases succeed" do
      service = TestService.new(@user)
      result = service.call

      assert result[:success]
      assert_equal "All phases completed", result[:message]
    end

    test "call handles errors gracefully" do
      service = Class.new(Base) do
        def search
          raise StandardError, "Database connection failed"
        end
      end.new(@user)

      result = service.call

      refute result[:success]
      assert_match(/error occurred/i, result[:error])
      assert_match(/Database connection failed/, result[:error])
    end

    test "phases can be overridden in subclass" do
      custom_service = Class.new(Base) do
        def search
          { custom: "data" }
        end

        def respond(data)
          success_result("Custom response", data)
        end
      end.new(@user)

      result = custom_service.call

      assert result[:success]
      assert_equal "Custom response", result[:message]
      assert_equal "data", result[:custom]
    end

    test "default search returns empty hash" do
      service = Base.new(@user)
      result = service.send(:search)

      assert_equal({}, result)
    end

    test "default process returns data unchanged" do
      service = Base.new(@user)
      data = { foo: "bar" }
      result = service.send(:process, data)

      assert_equal data, result
    end

    test "default transform returns data unchanged" do
      service = Base.new(@user)
      data = { foo: "bar" }
      result = service.send(:transform, data)

      assert_equal data, result
    end

    # ========================================
    # Config DSL - allow_nil_user Tests
    # ========================================

    # Service that allows nil user
    class SystemService < Base
      self._allow_nil_user = true
    end

    test "allow_nil_user defaults to false" do
      assert_equal false, Base._allow_nil_user
    end

    test "allow_nil_user can be set to true" do
      assert_equal true, SystemService._allow_nil_user
    end

    test "service with allow_nil_user true accepts nil user" do
      service = SystemService.new(nil, params: { foo: "bar" })

      assert_nil service.user
      assert_equal({ foo: "bar" }, service.params)
    end

    test "service with allow_nil_user true can still accept user" do
      service = SystemService.new(@user, params: {})

      assert_equal @user, service.user
    end

    test "allow_nil_user is inherited by subclasses" do
      subclass = Class.new(SystemService)

      assert_equal true, subclass._allow_nil_user
    end

    # ========================================
    # Schema Validation Tests
    # ========================================

    # Service with schema validation
    class ValidatedService < Base
      schema do
        required(:name).filled(:string)
        required(:age).filled(:integer)
        optional(:email).filled(:string)
      end
    end

    test "validates params with schema" do
      service = ValidatedService.new(@user, params: { name: "John", age: 30 })

      assert service.valid?
      assert_empty service.validation_errors
    end

    test "stores validation errors on failure" do
      service = ValidatedService.new(@user, params: { name: "", age: "invalid" })

      refute service.valid?
      assert service.validation_errors.key?(:name)
      assert service.validation_errors.key?(:age)
    end

    test "call returns failure if validation fails" do
      service = ValidatedService.new(@user, params: { name: "", age: "not_a_number" })
      result = service.call

      refute result[:success]
      assert_match(/validation failed/i, result[:error])
      assert result[:errors].is_a?(Hash)
    end

    test "validation errors formatted correctly" do
      service = ValidatedService.new(@user, params: { name: "", age: "invalid" })

      errors = service.validation_errors
      assert errors.is_a?(Hash)
      assert errors[:name].is_a?(Array)
      assert errors[:age].is_a?(Array)
    end

    # ========================================
    # Phase Blocks DSL Tests
    # ========================================

    # Service using phase blocks DSL
    class BlockBasedService < Base
      search_with do
        { users: ["Alice", "Bob"] }
      end

      process_with do |data|
        { users: data[:users].map(&:upcase) }
      end

      transform_with do |data|
        { users: data[:users].join(", ") }
      end

      respond_with do |data|
        success_result("Users processed", data)
      end
    end

    test "service can define search phase with block" do
      service = BlockBasedService.new(@user)
      result = service.call

      assert result[:success]
      assert_equal "ALICE, BOB", result[:users]
    end

    test "phase blocks receive data from previous phase" do
      service = BlockBasedService.new(@user)
      result = service.call

      assert result[:success]
      assert_equal "Users processed", result[:message]
    end

    test "phase blocks DSL coexists with method overrides" do
      hybrid_service = Class.new(Base) do
        search_with do
          { value: 10 }
        end

        def process(data)
          { value: data[:value] * 2 }
        end

        respond_with do |data|
          success_result("Hybrid", value: data[:value] + 5)
        end
      end.new(@user)

      result = hybrid_service.call

      assert result[:success]
      assert_equal 25, result[:value] # (10 * 2) + 5
    end

    test "phase blocks are inherited by subclasses" do
      subclass = Class.new(BlockBasedService)
      service = subclass.new(@user)
      result = service.call

      assert result[:success]
      assert_equal "ALICE, BOB", result[:users]
    end
  end
end
