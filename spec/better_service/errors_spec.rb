# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterService::BetterServiceError do
  describe "#initialize" do
    context "with message only" do
      subject(:error) { described_class.new("Something went wrong") }

      it "sets the message" do
        expect(error.message).to eq("Something went wrong")
      end

      it "defaults code to nil" do
        expect(error.code).to be_nil
      end

      it "defaults original_error to nil" do
        expect(error.original_error).to be_nil
      end

      it "defaults context to empty hash" do
        expect(error.context).to eq({})
      end

      it "sets timestamp" do
        expect(error.timestamp).to respond_to(:to_time)
      end
    end

    context "with code" do
      subject(:error) { described_class.new("Error", code: :custom_error) }

      it "stores the code" do
        expect(error.code).to eq(:custom_error)
      end
    end

    context "with original_error" do
      let(:original) { StandardError.new("Original error") }
      subject(:error) { described_class.new("Wrapped error", original_error: original) }

      it "stores the original error" do
        expect(error.original_error).to eq(original)
      end
    end

    context "with context" do
      subject(:error) do
        described_class.new("Error", context: { user_id: 123, action: "create" })
      end

      it "stores user_id in context" do
        expect(error.context[:user_id]).to eq(123)
      end

      it "stores action in context" do
        expect(error.context[:action]).to eq("create")
      end
    end
  end

  describe "#to_h" do
    context "with all attributes" do
      subject(:error) do
        described_class.new("Test error", code: :test_code, context: { key: "value" })
      end

      it "returns error_class" do
        expect(error.to_h[:error_class]).to eq("BetterService::BetterServiceError")
      end

      it "returns message" do
        expect(error.to_h[:message]).to eq("Test error")
      end

      it "returns code" do
        expect(error.to_h[:code]).to eq(:test_code)
      end

      it "returns context" do
        expect(error.to_h[:context]).to eq({ key: "value" })
      end

      it "returns timestamp" do
        expect(error.to_h[:timestamp]).to be_present
      end
    end

    context "with original error" do
      let(:original) { StandardError.new("Original") }
      subject(:error) { described_class.new("Wrapped", original_error: original) }

      it "includes original error info" do
        expect(error.to_h[:original_error]).to be_present
      end

      it "includes original error class" do
        expect(error.to_h[:original_error][:class]).to eq("StandardError")
      end

      it "includes original error message" do
        expect(error.to_h[:original_error][:message]).to eq("Original")
      end
    end
  end

  describe "#detailed_message" do
    subject(:error) do
      described_class.new("Main message", code: :test_code, context: { key: "value" })
    end

    it "includes the message" do
      expect(error.detailed_message).to include("Main message")
    end

    it "includes the code" do
      expect(error.detailed_message).to include("test_code")
    end

    it "includes context key" do
      expect(error.detailed_message).to include("key")
    end
  end

  describe "#backtrace" do
    it "includes original error backtrace" do
      error = begin
        raise StandardError, "Original"
      rescue StandardError => e
        described_class.new("Wrapped", original_error: e)
      end

      expect(error.backtrace.join("\n")).to include("Original Error Backtrace")
    end
  end
end

RSpec.describe BetterService::ErrorCodes do
  describe "constants" do
    it "defines VALIDATION_FAILED" do
      expect(described_class::VALIDATION_FAILED).to eq(:validation_failed)
    end

    it "defines UNAUTHORIZED" do
      expect(described_class::UNAUTHORIZED).to eq(:unauthorized)
    end

    it "defines SCHEMA_REQUIRED" do
      expect(described_class::SCHEMA_REQUIRED).to eq(:schema_required)
    end

    it "defines CONFIGURATION_ERROR" do
      expect(described_class::CONFIGURATION_ERROR).to eq(:configuration_error)
    end

    it "defines EXECUTION_ERROR" do
      expect(described_class::EXECUTION_ERROR).to eq(:execution_error)
    end

    it "defines RESOURCE_NOT_FOUND" do
      expect(described_class::RESOURCE_NOT_FOUND).to eq(:resource_not_found)
    end

    it "defines TRANSACTION_ERROR" do
      expect(described_class::TRANSACTION_ERROR).to eq(:transaction_error)
    end

    it "defines DATABASE_ERROR" do
      expect(described_class::DATABASE_ERROR).to eq(:database_error)
    end

    it "defines WORKFLOW_FAILED" do
      expect(described_class::WORKFLOW_FAILED).to eq(:workflow_failed)
    end

    it "defines STEP_FAILED" do
      expect(described_class::STEP_FAILED).to eq(:step_failed)
    end

    it "defines ROLLBACK_FAILED" do
      expect(described_class::ROLLBACK_FAILED).to eq(:rollback_failed)
    end
  end
end

RSpec.describe BetterService::Errors::Configuration do
  describe BetterService::Errors::Configuration::ConfigurationError do
    subject(:error) { described_class.new("Config error") }

    it "inherits from BetterServiceError" do
      expect(error).to be_a(BetterService::BetterServiceError)
    end
  end

  describe BetterService::Errors::Configuration::SchemaRequiredError do
    subject(:error) do
      described_class.new(
        "Schema required",
        code: BetterService::ErrorCodes::SCHEMA_REQUIRED,
        context: { service: "TestService" }
      )
    end

    it "stores the code" do
      expect(error.code).to eq(:schema_required)
    end

    it "stores service in context" do
      expect(error.context[:service]).to eq("TestService")
    end
  end

  describe BetterService::Errors::Configuration::NilUserError do
    subject(:error) do
      described_class.new("User is nil", context: { service: "TestService" })
    end

    it "inherits from ConfigurationError" do
      expect(error).to be_a(BetterService::Errors::Configuration::ConfigurationError)
    end
  end

  describe BetterService::Errors::Configuration::InvalidSchemaError do
    subject(:error) { described_class.new("Invalid schema") }

    it "inherits from ConfigurationError" do
      expect(error).to be_a(BetterService::Errors::Configuration::ConfigurationError)
    end
  end

  describe BetterService::Errors::Configuration::InvalidConfigurationError do
    subject(:error) do
      described_class.new(
        "Invalid config",
        code: BetterService::ErrorCodes::CONFIGURATION_ERROR,
        context: { setting: "unknown" }
      )
    end

    it "stores the code" do
      expect(error.code).to eq(:configuration_error)
    end
  end
end

RSpec.describe BetterService::Errors::Runtime do
  describe BetterService::Errors::Runtime::RuntimeError do
    subject(:error) { described_class.new("Runtime error") }

    it "inherits from BetterServiceError" do
      expect(error).to be_a(BetterService::BetterServiceError)
    end
  end

  describe BetterService::Errors::Runtime::ValidationError do
    subject(:error) do
      described_class.new(
        "Validation failed",
        code: BetterService::ErrorCodes::VALIDATION_FAILED,
        context: { validation_errors: { name: [ "is required" ] } }
      )
    end

    it "stores the code" do
      expect(error.code).to eq(:validation_failed)
    end

    it "stores validation errors in context" do
      expect(error.context[:validation_errors]).to be_present
    end
  end

  describe BetterService::Errors::Runtime::AuthorizationError do
    subject(:error) do
      described_class.new("Not authorized", code: BetterService::ErrorCodes::UNAUTHORIZED)
    end

    it "inherits from RuntimeError" do
      expect(error).to be_a(BetterService::Errors::Runtime::RuntimeError)
    end

    it "stores the code" do
      expect(error.code).to eq(:unauthorized)
    end
  end

  describe BetterService::Errors::Runtime::ExecutionError do
    let(:original) { StandardError.new("Boom") }
    subject(:error) do
      described_class.new(
        "Execution failed",
        code: BetterService::ErrorCodes::EXECUTION_ERROR,
        original_error: original,
        context: { service: "TestService" }
      )
    end

    it "stores the code" do
      expect(error.code).to eq(:execution_error)
    end

    it "stores the original error" do
      expect(error.original_error).to eq(original)
    end
  end

  describe BetterService::Errors::Runtime::ResourceNotFoundError do
    subject(:error) do
      described_class.new(
        "Record not found",
        code: BetterService::ErrorCodes::RESOURCE_NOT_FOUND,
        context: { model: "User", id: 123 }
      )
    end

    it "stores the code" do
      expect(error.code).to eq(:resource_not_found)
    end

    it "stores model in context" do
      expect(error.context[:model]).to eq("User")
    end

    it "stores id in context" do
      expect(error.context[:id]).to eq(123)
    end
  end

  describe BetterService::Errors::Runtime::TransactionError do
    subject(:error) do
      described_class.new("Transaction failed", code: BetterService::ErrorCodes::TRANSACTION_ERROR)
    end

    it "inherits from RuntimeError" do
      expect(error).to be_a(BetterService::Errors::Runtime::RuntimeError)
    end

    it "stores the code" do
      expect(error.code).to eq(:transaction_error)
    end
  end

  describe BetterService::Errors::Runtime::DatabaseError do
    subject(:error) do
      described_class.new(
        "Database error",
        code: BetterService::ErrorCodes::DATABASE_ERROR,
        context: { constraint: "users_email_unique" }
      )
    end

    it "inherits from RuntimeError" do
      expect(error).to be_a(BetterService::Errors::Runtime::RuntimeError)
    end

    it "stores the code" do
      expect(error.code).to eq(:database_error)
    end
  end
end

RSpec.describe BetterService::Errors::Workflowable::Configuration do
  describe BetterService::Errors::Workflowable::Configuration::WorkflowConfigurationError do
    subject(:error) { described_class.new("Workflow config error") }

    it "inherits from ConfigurationError" do
      expect(error).to be_a(BetterService::Errors::Configuration::ConfigurationError)
    end
  end

  describe BetterService::Errors::Workflowable::Configuration::StepNotFoundError do
    subject(:error) do
      described_class.new(
        "Step not found",
        context: { step: :missing_step, workflow: "TestWorkflow" }
      )
    end

    it "stores step in context" do
      expect(error.context[:step]).to eq(:missing_step)
    end

    it "stores workflow in context" do
      expect(error.context[:workflow]).to eq("TestWorkflow")
    end
  end

  describe BetterService::Errors::Workflowable::Configuration::InvalidStepError do
    subject(:error) do
      described_class.new(
        "Invalid step",
        context: { step: :bad_step, reason: "missing service" }
      )
    end

    it "stores step in context" do
      expect(error.context[:step]).to eq(:bad_step)
    end

    it "stores reason in context" do
      expect(error.context[:reason]).to eq("missing service")
    end
  end

  describe BetterService::Errors::Workflowable::Configuration::DuplicateStepError do
    subject(:error) do
      described_class.new("Duplicate step", context: { step: :duplicate_step })
    end

    it "stores step in context" do
      expect(error.context[:step]).to eq(:duplicate_step)
    end
  end
end

RSpec.describe BetterService::Errors::Workflowable::Runtime do
  describe BetterService::Errors::Workflowable::Runtime::WorkflowRuntimeError do
    subject(:error) { described_class.new("Workflow runtime error") }

    it "inherits from RuntimeError" do
      expect(error).to be_a(BetterService::Errors::Runtime::RuntimeError)
    end
  end

  describe BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError do
    subject(:error) do
      described_class.new(
        "Workflow failed",
        code: BetterService::ErrorCodes::WORKFLOW_FAILED,
        context: { workflow: "TestWorkflow", steps_executed: [ :step1, :step2 ] }
      )
    end

    it "stores the code" do
      expect(error.code).to eq(:workflow_failed)
    end

    it "stores workflow in context" do
      expect(error.context[:workflow]).to eq("TestWorkflow")
    end
  end

  describe BetterService::Errors::Workflowable::Runtime::StepExecutionError do
    subject(:error) do
      described_class.new(
        "Step failed",
        code: BetterService::ErrorCodes::STEP_FAILED,
        context: { step: :failing_step, workflow: "TestWorkflow" }
      )
    end

    it "stores the code" do
      expect(error.code).to eq(:step_failed)
    end

    it "stores step in context" do
      expect(error.context[:step]).to eq(:failing_step)
    end
  end

  describe BetterService::Errors::Workflowable::Runtime::RollbackError do
    let(:original) { StandardError.new("Rollback failed") }
    subject(:error) do
      described_class.new(
        "Rollback error",
        code: BetterService::ErrorCodes::ROLLBACK_FAILED,
        original_error: original,
        context: { step: :step_with_rollback, executed_steps: [ :step1, :step2 ] }
      )
    end

    it "stores the code" do
      expect(error.code).to eq(:rollback_failed)
    end

    it "stores step in context" do
      expect(error.context[:step]).to eq(:step_with_rollback)
    end

    it "stores the original error" do
      expect(error.original_error).to eq(original)
    end
  end
end

RSpec.describe "Error inheritance hierarchy" do
  let(:all_error_classes) do
    [
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
  end

  it "all errors inherit from BetterServiceError" do
    all_error_classes.each do |error_class|
      expect(error_class).to be < BetterService::BetterServiceError
    end
  end

  it "errors can be caught by base class" do
    expect {
      raise BetterService::Errors::Runtime::ValidationError.new("Test")
    }.to raise_error(BetterService::BetterServiceError)
  end

  it "runtime errors can be caught by RuntimeError base" do
    expect {
      raise BetterService::Errors::Runtime::ValidationError.new("Test")
    }.to raise_error(BetterService::Errors::Runtime::RuntimeError)
  end

  it "configuration errors can be caught by ConfigurationError base" do
    expect {
      raise BetterService::Errors::Configuration::SchemaRequiredError.new("Test")
    }.to raise_error(BetterService::Errors::Configuration::ConfigurationError)
  end
end

RSpec.describe "Error inspect" do
  subject(:error) do
    BetterService::Errors::Runtime::ValidationError.new(
      "Validation failed",
      context: { field: "email" }
    )
  end

  it "includes class name" do
    expect(error.inspect).to include("ValidationError")
  end

  it "includes message" do
    expect(error.inspect).to include("Validation failed")
  end
end
