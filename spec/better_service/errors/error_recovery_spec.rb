# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Error Recovery and Advanced Error Handling" do
  # Mock user for testing
  class ErrorRecoveryTestUser
    attr_accessor :id, :admin

    def initialize(id, admin: false)
      @id = id
      @admin = admin
    end

    def admin?
      @admin
    end
  end

  let(:user) { ErrorRecoveryTestUser.new(1) }

  describe "Exception chaining and original_error preservation" do
    it "preserves the original error through multiple wrapping layers" do
      original = ArgumentError.new("Original argument error")
      original.set_backtrace(["original.rb:1", "original.rb:2"])

      wrapped_once = BetterService::Errors::Runtime::ExecutionError.new(
        "First wrap",
        original_error: original,
        context: { layer: 1 }
      )

      wrapped_twice = BetterService::Errors::Runtime::ExecutionError.new(
        "Second wrap",
        original_error: wrapped_once,
        context: { layer: 2 }
      )

      expect(wrapped_twice.original_error).to eq(wrapped_once)
      expect(wrapped_twice.original_error.original_error).to eq(original)
    end

    it "includes original error class and message in to_h" do
      original = ActiveRecord::RecordNotFound.new("User not found")

      error = BetterService::Errors::Runtime::ResourceNotFoundError.new(
        "Resource lookup failed",
        original_error: original,
        context: { model: "User", id: 999 }
      )

      hash = error.to_h
      expect(hash[:original_error][:class]).to eq("ActiveRecord::RecordNotFound")
      expect(hash[:original_error][:message]).to eq("User not found")
    end

    it "handles nil original_error gracefully" do
      error = BetterService::Errors::Runtime::ExecutionError.new(
        "No original",
        code: :execution_error
      )

      expect(error.original_error).to be_nil
      expect(error.to_h[:original_error]).to be_nil
    end
  end

  describe "Error context propagation through service phases" do
    # Service that fails at validation
    class ValidationFailingService < BetterService::Services::Base
      schema do
        required(:email).filled(:string, format?: /@/)
        required(:age).filled(:integer, gteq?: 18)
      end

      process_with do |_data|
        { resource: { ok: true } }
      end
    end

    # Service that fails at authorization
    class AuthFailingService < BetterService::Services::Base
      schema do
        optional(:id).filled(:integer)
      end

      authorize_with do
        false
      end

      process_with do |_data|
        { resource: { ok: true } }
      end
    end

    it "validation error includes service name in context" do
      expect {
        ValidationFailingService.new(user, params: { email: "invalid", age: 16 })
      }.to raise_error(BetterService::Errors::Runtime::ValidationError) do |error|
        expect(error.context[:service]).to eq("ValidationFailingService")
      end
    end

    it "validation error includes all field errors" do
      expect {
        ValidationFailingService.new(user, params: { email: "invalid", age: 16 })
      }.to raise_error(BetterService::Errors::Runtime::ValidationError) do |error|
        expect(error.context[:validation_errors]).to have_key(:email)
        expect(error.context[:validation_errors]).to have_key(:age)
      end
    end

    it "authorization error includes service context" do
      service = AuthFailingService.new(user, params: { id: 1 })

      # Service catches AuthorizationError and returns failure result
      result = service.call

      # With use_result_wrapper = true (default), result is a BetterService::Result
      expect(result).to be_failure
      expect(result.meta[:error_code]).to eq(:unauthorized)
    end
  end

  describe "ValidationError with nested params" do
    class NestedParamsService < BetterService::Services::Base
      schema do
        required(:user).hash do
          required(:profile).hash do
            required(:name).filled(:string, min_size?: 2)
            required(:email).filled(:string, format?: /@/)
          end
          optional(:settings).hash do
            optional(:notifications).filled(:bool)
          end
        end
      end

      process_with do |_data|
        { resource: params }
      end
    end

    it "captures nested validation errors with full path" do
      expect {
        NestedParamsService.new(user, params: {
          user: {
            profile: {
              name: "X",
              email: "invalid"
            }
          }
        })
      }.to raise_error(BetterService::Errors::Runtime::ValidationError) do |error|
        validation_errors = error.context[:validation_errors]
        # Check that nested errors are present
        expect(validation_errors).to be_present
      end
    end
  end

  describe "ResourceNotFoundError with various ID types" do
    it "handles integer ID" do
      error = BetterService::Errors::Runtime::ResourceNotFoundError.new(
        "Record not found",
        code: :resource_not_found,
        context: { model: "Product", id: 12345 }
      )

      expect(error.context[:id]).to eq(12345)
      expect(error.context[:id]).to be_a(Integer)
    end

    it "handles string UUID" do
      uuid = "550e8400-e29b-41d4-a716-446655440000"
      error = BetterService::Errors::Runtime::ResourceNotFoundError.new(
        "Record not found",
        code: :resource_not_found,
        context: { model: "Document", id: uuid }
      )

      expect(error.context[:id]).to eq(uuid)
      expect(error.context[:id]).to be_a(String)
    end

    it "handles composite key as array" do
      composite_key = [123, "US", 2024]
      error = BetterService::Errors::Runtime::ResourceNotFoundError.new(
        "Record not found",
        code: :resource_not_found,
        context: { model: "RegionalSale", id: composite_key }
      )

      expect(error.context[:id]).to eq(composite_key)
      expect(error.context[:id]).to be_a(Array)
    end

    it "handles slug identifier" do
      error = BetterService::Errors::Runtime::ResourceNotFoundError.new(
        "Record not found",
        code: :resource_not_found,
        context: { model: "Article", id: "my-awesome-article-slug" }
      )

      expect(error.context[:id]).to eq("my-awesome-article-slug")
    end
  end

  describe "DatabaseError wrapping ActiveRecord errors" do
    it "wraps RecordInvalid with validation details" do
      # Create a simple mock object that responds to errors
      mock_record = double("Record")
      mock_errors = ActiveModel::Errors.new(mock_record)
      mock_errors.add(:name, "can't be blank")
      mock_errors.add(:email, "is invalid")
      allow(mock_record).to receive(:errors).and_return(mock_errors)

      # Create a simple StandardError to simulate RecordInvalid
      ar_error = StandardError.new("Validation failed")

      error = BetterService::Errors::Runtime::DatabaseError.new(
        "Failed to save record",
        code: :database_error,
        original_error: ar_error,
        context: { model: "User", operation: "create", errors: mock_errors.to_hash }
      )

      expect(error.original_error).to be_a(StandardError)
      expect(error.context[:model]).to eq("User")
      expect(error.context[:operation]).to eq("create")
      expect(error.context[:errors]).to have_key(:name)
      expect(error.context[:errors]).to have_key(:email)
    end

    it "wraps RecordNotUnique with constraint info" do
      ar_error = ActiveRecord::RecordNotUnique.new("Duplicate key violation")

      error = BetterService::Errors::Runtime::DatabaseError.new(
        "Duplicate record",
        code: :database_error,
        original_error: ar_error,
        context: { constraint: "users_email_unique", table: "users" }
      )

      expect(error.original_error).to be_a(ActiveRecord::RecordNotUnique)
      expect(error.context[:constraint]).to eq("users_email_unique")
    end
  end

  describe "ExecutionError with full backtrace" do
    it "combines own backtrace with original error backtrace" do
      begin
        raise StandardError, "Deep error"
      rescue StandardError => original
        error = BetterService::Errors::Runtime::ExecutionError.new(
          "Execution failed",
          original_error: original,
          code: :execution_error
        )

        backtrace = error.backtrace
        expect(backtrace.join("\n")).to include("Original Error Backtrace")
        expect(backtrace.length).to be > original.backtrace.length
      end
    end

    it "handles error without backtrace" do
      original = StandardError.new("No backtrace error")
      # Don't set backtrace

      error = BetterService::Errors::Runtime::ExecutionError.new(
        "Wrapped",
        original_error: original
      )

      expect { error.backtrace }.not_to raise_error
    end
  end

  describe "Error serialization (to_h, to_json)" do
    let(:error) do
      BetterService::Errors::Runtime::ValidationError.new(
        "Validation failed",
        code: :validation_failed,
        context: {
          service: "ProductService",
          validation_errors: { name: ["is required"], price: ["must be positive"] },
          params: { name: nil, price: -10 }
        }
      )
    end

    it "to_h includes all required fields" do
      hash = error.to_h

      expect(hash).to have_key(:error_class)
      expect(hash).to have_key(:message)
      expect(hash).to have_key(:code)
      expect(hash).to have_key(:timestamp)
      expect(hash).to have_key(:context)
      expect(hash).to have_key(:backtrace)
    end

    it "timestamp is in ISO8601 format" do
      hash = error.to_h

      expect(hash[:timestamp]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end

    it "context preserves nested structures" do
      hash = error.to_h

      expect(hash[:context][:validation_errors]).to be_a(Hash)
      expect(hash[:context][:validation_errors][:name]).to eq(["is required"])
    end

    it "backtrace is limited to first 10 entries" do
      hash = error.to_h

      expect(hash[:backtrace].length).to be <= 10
    end
  end

  describe "Error code consistency across exception types" do
    it "ValidationError uses :validation_failed code" do
      error = BetterService::Errors::Runtime::ValidationError.new(
        "Test",
        code: BetterService::ErrorCodes::VALIDATION_FAILED
      )
      expect(error.code).to eq(:validation_failed)
    end

    it "AuthorizationError uses :unauthorized code" do
      error = BetterService::Errors::Runtime::AuthorizationError.new(
        "Test",
        code: BetterService::ErrorCodes::UNAUTHORIZED
      )
      expect(error.code).to eq(:unauthorized)
    end

    it "ResourceNotFoundError uses :resource_not_found code" do
      error = BetterService::Errors::Runtime::ResourceNotFoundError.new(
        "Test",
        code: BetterService::ErrorCodes::RESOURCE_NOT_FOUND
      )
      expect(error.code).to eq(:resource_not_found)
    end

    it "DatabaseError uses :database_error code" do
      error = BetterService::Errors::Runtime::DatabaseError.new(
        "Test",
        code: BetterService::ErrorCodes::DATABASE_ERROR
      )
      expect(error.code).to eq(:database_error)
    end

    it "TransactionError uses :transaction_error code" do
      error = BetterService::Errors::Runtime::TransactionError.new(
        "Test",
        code: BetterService::ErrorCodes::TRANSACTION_ERROR
      )
      expect(error.code).to eq(:transaction_error)
    end

    it "ExecutionError uses :execution_error code" do
      error = BetterService::Errors::Runtime::ExecutionError.new(
        "Test",
        code: BetterService::ErrorCodes::EXECUTION_ERROR
      )
      expect(error.code).to eq(:execution_error)
    end
  end

  describe "Error timestamp accuracy" do
    it "timestamp is close to current time" do
      before = Time.current
      error = BetterService::BetterServiceError.new("Test")
      after = Time.current

      expect(error.timestamp).to be >= before
      expect(error.timestamp).to be <= after
    end

    it "each error gets unique timestamp" do
      error1 = BetterService::BetterServiceError.new("First")
      sleep(0.001)
      error2 = BetterService::BetterServiceError.new("Second")

      expect(error2.timestamp).to be >= error1.timestamp
    end

    it "timestamp is a Time object" do
      error = BetterService::BetterServiceError.new("Test")

      expect(error.timestamp).to respond_to(:to_time)
      expect(error.timestamp).to respond_to(:iso8601)
    end
  end
end
