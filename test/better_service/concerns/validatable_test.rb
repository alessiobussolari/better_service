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
      class ValidatedService < Base
        schema do
          required(:name).filled(:string)
          required(:age).filled(:integer)
          optional(:email).filled(:string)
        end
      end

      # Service with custom validation rules
      class PagedService < Base
        schema do
          required(:page).filled(:integer, gteq?: 1)
        end
      end

      # Service with email format validation
      class EmailService < Base
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
        assert_not_nil Base._schema
        assert_instance_of Dry::Schema::Params, Base._schema
      end

      # ========================================
      # Test Group 2: Validation Execution
      # ========================================

      test "validates valid params successfully" do
        service = ValidatedService.new(@user, params: { name: "John", age: 30 })

        assert service.valid?
        assert_empty service.validation_errors
      end

      test "catches validation errors for invalid params" do
        service = ValidatedService.new(@user, params: { name: "", age: "not_number" })

        refute service.valid?
        assert service.validation_errors.key?(:name)
        assert service.validation_errors.key?(:age)
      end

      test "validation fails when required field missing" do
        service = ValidatedService.new(@user, params: { age: 30 })

        refute service.valid?
        assert service.validation_errors.key?(:name)
      end

      test "validation passes when optional field omitted" do
        service = ValidatedService.new(@user, params: { name: "John", age: 30 })

        assert service.valid?
      end

      test "validation catches type mismatches" do
        service = ValidatedService.new(@user, params: { name: "John", age: "twenty" })

        refute service.valid?
        assert service.validation_errors.key?(:age)
      end

      test "validation respects custom rules (gteq?)" do
        service = PagedService.new(@user, params: { page: 0 })

        refute service.valid?
        assert service.validation_errors.key?(:page)
      end

      # ========================================
      # Test Group 3: Error Formatting
      # ========================================

      test "validation errors formatted as arrays" do
        service = ValidatedService.new(@user, params: { name: "", age: "bad" })

        service.validation_errors.each_value do |messages|
          assert messages.is_a?(Array)
        end
      end

      test "multiple errors for same field collected in array" do
        service = EmailService.new(@user, params: { email: "" })

        refute service.valid?
        assert service.validation_errors[:email].is_a?(Array)
      end

      test "validation errors have correct structure" do
        service = ValidatedService.new(@user, params: { name: "" })

        errors = service.validation_errors
        assert errors.is_a?(Hash)
        assert errors[:name].is_a?(Array)
        assert errors[:name].all? { |e| e.is_a?(String) }
      end

      test "validation errors empty when params valid" do
        service = ValidatedService.new(@user, params: { name: "John", age: 30 })

        assert_empty service.validation_errors
      end

      # ========================================
      # Test Group 4: Integration with Call Flow
      # ========================================

      test "call returns failure result when validation fails" do
        service = ValidatedService.new(@user, params: { name: "" })
        result = service.call

        refute result[:success]
        assert_match(/validation failed/i, result[:error])
        assert result[:errors].is_a?(Hash)
      end

      test "search phase not executed when validation fails" do
        search_called = false

        service = Class.new(Base) do
          schema do
            required(:id).filled(:string)
          end

          define_method(:search) do
            search_called = true
            raise "Should not be called"
          end
        end.new(@user, params: {})

        result = service.call

        refute result[:success]
        refute search_called
      end

      test "validation happens before search phase" do
        executed_phases = []

        service = Class.new(Base) do
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

      test "validation errors included in failure result" do
        service = ValidatedService.new(@user, params: { name: "", age: "bad" })
        result = service.call

        assert result[:errors].key?(:name)
        assert result[:errors].key?(:age)
      end

      test "no validation performed when schema not defined" do
        service = Base.new(@user, params: { anything: "goes" })

        assert service.valid?
        result = service.call
        assert result[:success]
      end
    end
  end
end
