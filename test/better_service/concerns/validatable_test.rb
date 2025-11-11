# frozen_string_literal: true

require "test_helper"

module BetterService
  module Concerns
    class ValidatableTest < ActiveSupport::TestCase
      # Dummy user class for testing
      class DummyUser
        attr_accessor :id, :name

        def initialize(id: 1, name: "Test User")
          @id = id
          @name = name
        end
      end

      # Service with schema validation
      class ValidatedService < Services::Base
        schema do
          required(:name).filled(:string)
          required(:age).filled(:integer)
          optional(:email).filled(:string)
        end
      end

      # Service with custom validation rules
      class PagedService < Services::Base
        schema do
          required(:page).filled(:integer, gteq?: 1)
        end
      end

      # Service with email format validation
      class EmailService < Services::Base
        schema do
          required(:email).filled(:string, format?: /@/)
        end
      end

      def setup
        @user = DummyUser.new
      end

      # ========================================
      # Test Group 1: Schema Definition
      # ========================================

      test "schema DSL defines _schema class attribute" do
        assert_not_nil ValidatedService._schema
        assert_kind_of Dry::Schema::Params, ValidatedService._schema
      end

      test "schema is inherited by subclasses" do
        subclass = Class.new(ValidatedService)

        assert_not_nil subclass._schema
      end

      test "Base has default empty schema" do
        assert_not_nil Services::Base._schema
        assert_instance_of Dry::Schema::Params, Services::Base._schema
      end

      # ========================================
      # Test Group 2: Validation Execution
      # ========================================

      test "raises ValidationError for invalid params during initialize" do
        error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
          ValidatedService.new(@user, params: { name: "", age: "not_number" })
        end

        assert error.context[:validation_errors].key?(:name)
        assert error.context[:validation_errors].key?(:age)
      end

      test "raises ValidationError when required field missing" do
        error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
          ValidatedService.new(@user, params: { age: 30 })
        end

        assert error.context[:validation_errors].key?(:name)
      end

      test "raises ValidationError for type mismatches" do
        error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
          ValidatedService.new(@user, params: { name: "John", age: "twenty" })
        end

        assert error.context[:validation_errors].key?(:age)
      end

      test "raises ValidationError when custom rules fail" do
        error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
          PagedService.new(@user, params: { page: 0 })
        end

        assert error.context[:validation_errors].key?(:page)
      end

      # ========================================
      # Test Group 3: Error Formatting
      # ========================================

      test "validation errors formatted as arrays in exception context" do
        error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
          ValidatedService.new(@user, params: { name: "", age: "bad" })
        end

        error.context[:validation_errors].each_value do |messages|
          assert messages.is_a?(Array)
        end
      end

      test "multiple errors for same field collected in array" do
        error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
          EmailService.new(@user, params: { email: "" })
        end

        assert error.context[:validation_errors][:email].is_a?(Array)
      end

      test "validation errors have correct structure in exception context" do
        error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
          ValidatedService.new(@user, params: { name: "" })
        end

        errors = error.context[:validation_errors]
        assert errors.is_a?(Hash)
        assert errors[:name].is_a?(Array)
        assert errors[:name].all? { |e| e.is_a?(String) }
      end

      # ========================================
      # Test Group 4: Integration with Call Flow
      # ========================================

      test "initialize raises ValidationError when validation fails" do
        error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
          ValidatedService.new(@user, params: { name: "" })
        end

        assert_equal :validation_failed, error.code
        assert error.context[:validation_errors].is_a?(Hash)
        assert error.context[:validation_errors].key?(:name)
      end

      test "search phase not executed when validation fails" do
        search_called = false

        service_class = Class.new(Services::Base) do
          schema do
            required(:id).filled(:string)
          end

          define_method(:search) do
            search_called = true
            raise "Should not be called"
          end
        end

        error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
          service_class.new(@user, params: {})
        end

        assert_equal :validation_failed, error.code
        refute search_called
      end

      test "validation happens before search phase" do
        executed_phases = []

        service = Class.new(Services::Base) do
          schema do
            required(:name).filled(:string)
          end

          search_with do
            executed_phases << :search
            {}
          end
        end.new(@user, params: { name: "John" })

        service.call

        assert_includes executed_phases, :search
      end

      test "validation errors included in exception context" do
        error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
          ValidatedService.new(@user, params: { name: "", age: "bad" })
        end

        assert error.context[:validation_errors].key?(:name)
        assert error.context[:validation_errors].key?(:age)
      end
    end
  end
end
