# frozen_string_literal: true

require "test_helper"

class BetterService::ErrorsTest < ActiveSupport::TestCase
  # =====================
  # BetterServiceError tests
  # =====================

  test "BetterServiceError can be instantiated with message only" do
    error = BetterService::BetterServiceError.new("Something went wrong")

    assert_equal "Something went wrong", error.message
    assert_nil error.code
    assert_nil error.original_error
    assert_equal({}, error.context)
    assert error.timestamp.respond_to?(:to_time), "timestamp should be a Time-like object"
  end

  test "BetterServiceError stores code" do
    error = BetterService::BetterServiceError.new(
      "Error",
      code: :custom_error
    )

    assert_equal :custom_error, error.code
  end

  test "BetterServiceError stores original error" do
    original = StandardError.new("Original error")

    error = BetterService::BetterServiceError.new(
      "Wrapped error",
      original_error: original
    )

    assert_equal original, error.original_error
  end

  test "BetterServiceError stores context" do
    error = BetterService::BetterServiceError.new(
      "Error",
      context: { user_id: 123, action: "create" }
    )

    assert_equal 123, error.context[:user_id]
    assert_equal "create", error.context[:action]
  end

  test "BetterServiceError to_h returns structured hash" do
    error = BetterService::BetterServiceError.new(
      "Test error",
      code: :test_code,
      context: { key: "value" }
    )

    hash = error.to_h

    assert_equal "BetterService::BetterServiceError", hash[:error_class]
    assert_equal "Test error", hash[:message]
    assert_equal :test_code, hash[:code]
    assert_equal({ key: "value" }, hash[:context])
    assert hash[:timestamp].present?
  end

  test "BetterServiceError to_h includes original error info" do
    original = StandardError.new("Original")
    error = BetterService::BetterServiceError.new(
      "Wrapped",
      original_error: original
    )

    hash = error.to_h

    assert hash[:original_error].present?
    assert_equal "StandardError", hash[:original_error][:class]
    assert_equal "Original", hash[:original_error][:message]
  end

  test "BetterServiceError detailed_message includes all parts" do
    error = BetterService::BetterServiceError.new(
      "Main message",
      code: :test_code,
      context: { key: "value" }
    )

    detailed = error.detailed_message

    assert_includes detailed, "Main message"
    assert_includes detailed, "test_code"
    assert_includes detailed, "key"
  end

  test "BetterServiceError backtrace includes original error backtrace" do
    begin
      raise StandardError, "Original"
    rescue StandardError => e
      error = BetterService::BetterServiceError.new(
        "Wrapped",
        original_error: e
      )

      assert_includes error.backtrace.join("\n"), "Original Error Backtrace"
    end
  end

  # =====================
  # ErrorCodes tests
  # =====================

  test "ErrorCodes defines all expected codes" do
    assert_equal :validation_failed, BetterService::ErrorCodes::VALIDATION_FAILED
    assert_equal :unauthorized, BetterService::ErrorCodes::UNAUTHORIZED
    assert_equal :schema_required, BetterService::ErrorCodes::SCHEMA_REQUIRED
    assert_equal :configuration_error, BetterService::ErrorCodes::CONFIGURATION_ERROR
    assert_equal :execution_error, BetterService::ErrorCodes::EXECUTION_ERROR
    assert_equal :resource_not_found, BetterService::ErrorCodes::RESOURCE_NOT_FOUND
    assert_equal :transaction_error, BetterService::ErrorCodes::TRANSACTION_ERROR
    assert_equal :database_error, BetterService::ErrorCodes::DATABASE_ERROR
    assert_equal :workflow_failed, BetterService::ErrorCodes::WORKFLOW_FAILED
    assert_equal :step_failed, BetterService::ErrorCodes::STEP_FAILED
    assert_equal :rollback_failed, BetterService::ErrorCodes::ROLLBACK_FAILED
  end

  # =====================
  # Configuration error tests
  # =====================

  test "ConfigurationError is a BetterServiceError" do
    error = BetterService::Errors::Configuration::ConfigurationError.new("Config error")

    assert_kind_of BetterService::BetterServiceError, error
  end

  test "SchemaRequiredError can be created with code" do
    error = BetterService::Errors::Configuration::SchemaRequiredError.new(
      "Schema required",
      code: BetterService::ErrorCodes::SCHEMA_REQUIRED,
      context: { service: "TestService" }
    )

    assert_equal :schema_required, error.code
    assert_equal "TestService", error.context[:service]
  end

  test "NilUserError is a ConfigurationError" do
    error = BetterService::Errors::Configuration::NilUserError.new(
      "User is nil",
      context: { service: "TestService" }
    )

    assert_kind_of BetterService::Errors::Configuration::ConfigurationError, error
  end

  test "InvalidSchemaError is a ConfigurationError" do
    error = BetterService::Errors::Configuration::InvalidSchemaError.new(
      "Invalid schema"
    )

    assert_kind_of BetterService::Errors::Configuration::ConfigurationError, error
  end

  test "InvalidConfigurationError can be created with code" do
    error = BetterService::Errors::Configuration::InvalidConfigurationError.new(
      "Invalid config",
      code: BetterService::ErrorCodes::CONFIGURATION_ERROR,
      context: { setting: "unknown" }
    )

    assert_equal :configuration_error, error.code
  end

  # =====================
  # Runtime error tests
  # =====================

  test "RuntimeError is a BetterServiceError" do
    error = BetterService::Errors::Runtime::RuntimeError.new("Runtime error")

    assert_kind_of BetterService::BetterServiceError, error
  end

  test "ValidationError stores validation errors in context" do
    error = BetterService::Errors::Runtime::ValidationError.new(
      "Validation failed",
      code: BetterService::ErrorCodes::VALIDATION_FAILED,
      context: { validation_errors: { name: ["is required"] } }
    )

    assert_equal :validation_failed, error.code
    assert error.context[:validation_errors].present?
  end

  test "AuthorizationError is a RuntimeError" do
    error = BetterService::Errors::Runtime::AuthorizationError.new(
      "Not authorized",
      code: BetterService::ErrorCodes::UNAUTHORIZED
    )

    assert_kind_of BetterService::Errors::Runtime::RuntimeError, error
    assert_equal :unauthorized, error.code
  end

  test "ExecutionError stores original error" do
    original = StandardError.new("Boom")

    error = BetterService::Errors::Runtime::ExecutionError.new(
      "Execution failed",
      code: BetterService::ErrorCodes::EXECUTION_ERROR,
      original_error: original,
      context: { service: "TestService" }
    )

    assert_equal :execution_error, error.code
    assert_equal original, error.original_error
  end

  test "ResourceNotFoundError stores resource info" do
    error = BetterService::Errors::Runtime::ResourceNotFoundError.new(
      "Record not found",
      code: BetterService::ErrorCodes::RESOURCE_NOT_FOUND,
      context: { model: "User", id: 123 }
    )

    assert_equal :resource_not_found, error.code
    assert_equal "User", error.context[:model]
    assert_equal 123, error.context[:id]
  end

  test "TransactionError is a RuntimeError" do
    error = BetterService::Errors::Runtime::TransactionError.new(
      "Transaction failed",
      code: BetterService::ErrorCodes::TRANSACTION_ERROR
    )

    assert_kind_of BetterService::Errors::Runtime::RuntimeError, error
    assert_equal :transaction_error, error.code
  end

  test "DatabaseError is a RuntimeError" do
    error = BetterService::Errors::Runtime::DatabaseError.new(
      "Database error",
      code: BetterService::ErrorCodes::DATABASE_ERROR,
      context: { constraint: "users_email_unique" }
    )

    assert_kind_of BetterService::Errors::Runtime::RuntimeError, error
    assert_equal :database_error, error.code
  end

  # =====================
  # Workflowable configuration error tests
  # =====================

  test "WorkflowConfigurationError is a ConfigurationError" do
    error = BetterService::Errors::Workflowable::Configuration::WorkflowConfigurationError.new(
      "Workflow config error"
    )

    assert_kind_of BetterService::Errors::Configuration::ConfigurationError, error
  end

  test "StepNotFoundError stores step context" do
    error = BetterService::Errors::Workflowable::Configuration::StepNotFoundError.new(
      "Step not found",
      context: { step: :missing_step, workflow: "TestWorkflow" }
    )

    assert_equal :missing_step, error.context[:step]
    assert_equal "TestWorkflow", error.context[:workflow]
  end

  test "InvalidStepError stores step context" do
    error = BetterService::Errors::Workflowable::Configuration::InvalidStepError.new(
      "Invalid step",
      context: { step: :bad_step, reason: "missing service" }
    )

    assert_equal :bad_step, error.context[:step]
    assert_equal "missing service", error.context[:reason]
  end

  test "DuplicateStepError stores step context" do
    error = BetterService::Errors::Workflowable::Configuration::DuplicateStepError.new(
      "Duplicate step",
      context: { step: :duplicate_step }
    )

    assert_equal :duplicate_step, error.context[:step]
  end

  # =====================
  # Workflowable runtime error tests
  # =====================

  test "WorkflowRuntimeError is a RuntimeError" do
    error = BetterService::Errors::Workflowable::Runtime::WorkflowRuntimeError.new(
      "Workflow runtime error"
    )

    assert_kind_of BetterService::Errors::Runtime::RuntimeError, error
  end

  test "WorkflowExecutionError stores workflow info" do
    error = BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError.new(
      "Workflow failed",
      code: BetterService::ErrorCodes::WORKFLOW_FAILED,
      context: { workflow: "TestWorkflow", steps_executed: [:step1, :step2] }
    )

    assert_equal :workflow_failed, error.code
    assert_equal "TestWorkflow", error.context[:workflow]
  end

  test "StepExecutionError stores step info" do
    error = BetterService::Errors::Workflowable::Runtime::StepExecutionError.new(
      "Step failed",
      code: BetterService::ErrorCodes::STEP_FAILED,
      context: { step: :failing_step, workflow: "TestWorkflow" }
    )

    assert_equal :step_failed, error.code
    assert_equal :failing_step, error.context[:step]
  end

  test "RollbackError stores rollback info" do
    original = StandardError.new("Rollback failed")

    error = BetterService::Errors::Workflowable::Runtime::RollbackError.new(
      "Rollback error",
      code: BetterService::ErrorCodes::ROLLBACK_FAILED,
      original_error: original,
      context: { step: :step_with_rollback, executed_steps: [:step1, :step2] }
    )

    assert_equal :rollback_failed, error.code
    assert_equal :step_with_rollback, error.context[:step]
    assert_equal original, error.original_error
  end

  # =====================
  # Error inheritance hierarchy tests
  # =====================

  test "all errors inherit from BetterServiceError" do
    errors = [
      BetterService::Errors::Configuration::ConfigurationError,
      BetterService::Errors::Configuration::SchemaRequiredError,
      BetterService::Errors::Configuration::NilUserError,
      BetterService::Errors::Configuration::InvalidSchemaError,
      BetterService::Errors::Configuration::InvalidConfigurationError,
      BetterService::Errors::Runtime::RuntimeError,
      BetterService::Errors::Runtime::ValidationError,
      BetterService::Errors::Runtime::AuthorizationError,
      BetterService::Errors::Runtime::ExecutionError,
      BetterService::Errors::Runtime::ResourceNotFoundError,
      BetterService::Errors::Runtime::TransactionError,
      BetterService::Errors::Runtime::DatabaseError,
      BetterService::Errors::Workflowable::Configuration::WorkflowConfigurationError,
      BetterService::Errors::Workflowable::Configuration::StepNotFoundError,
      BetterService::Errors::Workflowable::Configuration::InvalidStepError,
      BetterService::Errors::Workflowable::Configuration::DuplicateStepError,
      BetterService::Errors::Workflowable::Runtime::WorkflowRuntimeError,
      BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError,
      BetterService::Errors::Workflowable::Runtime::StepExecutionError,
      BetterService::Errors::Workflowable::Runtime::RollbackError
    ]

    errors.each do |error_class|
      assert error_class < BetterService::BetterServiceError,
             "#{error_class.name} should inherit from BetterServiceError"
    end
  end

  test "errors can be caught by base class" do
    assert_raises(BetterService::BetterServiceError) do
      raise BetterService::Errors::Runtime::ValidationError.new("Test")
    end
  end

  test "runtime errors can be caught by RuntimeError base" do
    assert_raises(BetterService::Errors::Runtime::RuntimeError) do
      raise BetterService::Errors::Runtime::ValidationError.new("Test")
    end
  end

  test "configuration errors can be caught by ConfigurationError base" do
    assert_raises(BetterService::Errors::Configuration::ConfigurationError) do
      raise BetterService::Errors::Configuration::SchemaRequiredError.new("Test")
    end
  end

  # =====================
  # Error inspect tests
  # =====================

  test "error inspect includes class name and message" do
    error = BetterService::Errors::Runtime::ValidationError.new(
      "Validation failed",
      context: { field: "email" }
    )

    inspect_str = error.inspect

    assert_includes inspect_str, "ValidationError"
    assert_includes inspect_str, "Validation failed"
  end
end
