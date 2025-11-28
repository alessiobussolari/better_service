# frozen_string_literal: true

require "test_helper"

class BetterService::Workflows::TransactionSupportTest < ActiveSupport::TestCase
  class User
    attr_accessor :id, :name
    def initialize(id, name: "Test User")
      @id = id
      @name = name
    end
  end

  # Mock service that creates a record (simulates database write)
  class CreateRecordService < BetterService::Services::Base
    schema do
      optional(:name).maybe(:string)
      optional(:should_fail).maybe(:bool)
    end

    process_with do |_data|
      if params[:should_fail]
        raise StandardError, "Service failed intentionally"
      end

      # Simulate creating a record
      { resource: { id: rand(1000), name: params[:name] || "Default", created_at: Time.current } }
    end
  end

  # Mock service that always succeeds
  class SuccessService < BetterService::Services::Base
    schema do
      optional(:value).maybe(:integer)
    end

    process_with do |_data|
      { resource: { value: params[:value] || 42 } }
    end
  end

  # Workflow with transaction enabled
  class TransactionalWorkflow < BetterService::Workflows::Base
    with_transaction true

    step :create_record,
         with: CreateRecordService,
         input: ->(ctx) { { name: ctx.record_name } }

    step :process_data,
         with: SuccessService
  end

  # Workflow with transaction disabled (default)
  class NonTransactionalWorkflow < BetterService::Workflows::Base
    with_transaction false

    step :step_one,
         with: SuccessService

    step :step_two,
         with: SuccessService
  end

  # Workflow that fails mid-execution with transaction
  class FailingTransactionalWorkflow < BetterService::Workflows::Base
    with_transaction true

    step :first_step,
         with: SuccessService

    step :failing_step,
         with: CreateRecordService,
         input: ->(ctx) { { should_fail: true } }

    step :unreachable_step,
         with: SuccessService
  end

  setup do
    @user = User.new(1)
  end

  # =====================
  # Transaction Configuration tests
  # =====================

  test "with_transaction enables transaction for workflow" do
    assert TransactionalWorkflow._use_transaction
  end

  test "with_transaction false disables transaction" do
    assert_not NonTransactionalWorkflow._use_transaction
  end

  test "transaction is disabled by default" do
    # Create an anonymous workflow class without with_transaction
    workflow_class = Class.new(BetterService::Workflows::Base) do
      step :simple_step, with: SuccessService
    end

    assert_not workflow_class._use_transaction
  end

  # =====================
  # Successful transaction tests
  # =====================

  test "transactional workflow executes successfully" do
    workflow = TransactionalWorkflow.new(@user, params: {})
    workflow.instance_variable_get(:@context).record_name = "Test Record"

    result = workflow.call

    assert result[:success]
    assert_equal [:create_record, :process_data], result[:metadata][:steps_executed]
  end

  test "transactional workflow stores results in context" do
    workflow = TransactionalWorkflow.new(@user, params: {})
    workflow.instance_variable_get(:@context).record_name = "My Record"

    result = workflow.call

    assert result[:success]
    assert_equal "My Record", result[:context].create_record[:name]
  end

  test "non-transactional workflow executes all steps" do
    workflow = NonTransactionalWorkflow.new(@user, params: {})
    result = workflow.call

    assert result[:success]
    assert_equal [:step_one, :step_two], result[:metadata][:steps_executed]
  end

  # =====================
  # Transaction rollback tests
  # =====================

  test "transactional workflow triggers rollback on failure" do
    error = assert_raises(BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError) do
      FailingTransactionalWorkflow.new(@user, params: {}).call
    end

    assert_equal :workflow_failed, error.code
    assert_includes error.message, "Service failed intentionally"
  end

  test "steps after failure are not executed" do
    workflow = FailingTransactionalWorkflow.new(@user, params: {})

    assert_raises(BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError) do
      workflow.call
    end

    # Check executed steps from workflow instance
    executed_names = workflow.instance_variable_get(:@executed_steps).map(&:name)
    assert_includes executed_names, :first_step
    assert_not_includes executed_names, :unreachable_step
  end

  # =====================
  # Execute with transaction tests
  # =====================

  test "transactional workflow uses execute_with_transaction" do
    workflow = TransactionalWorkflow.new(@user, params: {})
    workflow.instance_variable_get(:@context).record_name = "Test"

    # Transactional workflows use execute_with_transaction
    assert TransactionalWorkflow._use_transaction

    result = workflow.call
    assert result[:success]
  end

  test "non-transactional workflow uses execute_workflow directly" do
    workflow = NonTransactionalWorkflow.new(@user, params: {})

    # Non-transactional workflows skip execute_with_transaction
    assert_not NonTransactionalWorkflow._use_transaction

    result = workflow.call
    assert result[:success]
  end

  # =====================
  # Transaction behavior with exceptions
  # =====================

  test "workflow execution error is raised on failure" do
    # Create a workflow that fails
    workflow_class = Class.new(BetterService::Workflows::Base) do
      with_transaction true

      step :fail_step,
           with: Class.new(BetterService::Services::Base) {
             schema {}
             process_with { raise StandardError, "Boom!" }
           }
    end

    error = assert_raises(BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError) do
      workflow_class.new(@user, params: {}).call
    end

    assert_equal :workflow_failed, error.code
    assert_includes error.message, "Boom!"
  end

  # =====================
  # Context preservation tests
  # =====================

  test "context is preserved after successful transaction" do
    workflow = TransactionalWorkflow.new(@user, params: {})
    workflow.instance_variable_get(:@context).record_name = "Preserved Record"

    result = workflow.call

    assert result[:context].respond_to?(:create_record)
    assert_equal "Preserved Record", result[:context].create_record[:name]
  end

  test "context contains user after workflow" do
    workflow = TransactionalWorkflow.new(@user, params: {})
    workflow.instance_variable_get(:@context).record_name = "Test"

    result = workflow.call

    assert_equal @user, result[:context].user
  end

  # =====================
  # Mixed workflow tests
  # =====================

  test "workflow chooses correct execution path based on transaction setting" do
    # Transactional workflow
    transactional = TransactionalWorkflow.new(@user, params: {})
    transactional.instance_variable_get(:@context).record_name = "Trans"

    # Non-transactional workflow
    non_transactional = NonTransactionalWorkflow.new(@user, params: {})

    # Both should succeed
    trans_result = transactional.call
    non_trans_result = non_transactional.call

    assert trans_result[:success]
    assert non_trans_result[:success]
  end
end
