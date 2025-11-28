# frozen_string_literal: true

require "test_helper"

class BetterService::Workflows::RollbackSupportTest < ActiveSupport::TestCase
  class User
    attr_accessor :id, :name
    def initialize(id, name: "Test User")
      @id = id
      @name = name
    end
  end

  # Tracking module to record rollback calls
  module RollbackTracker
    class << self
      attr_accessor :rollback_calls, :rollback_order

      def reset!
        @rollback_calls = []
        @rollback_order = []
      end

      def track(step_name)
        @rollback_calls ||= []
        @rollback_order ||= []
        @rollback_calls << step_name
        @rollback_order << step_name
      end
    end
  end

  # Service that succeeds
  class SuccessService < BetterService::Services::Base
    schema do
      optional(:value).maybe(:integer)
      optional(:step_name).maybe(:string)
    end

    process_with do |_data|
      { resource: { value: params[:value] || 42, step: params[:step_name] } }
    end
  end

  # Service that always fails
  class FailingService < BetterService::Services::Base
    schema {}

    process_with do |_data|
      raise StandardError, "Service intentionally failed"
    end
  end

  # Service with rollback that fails
  class FailingRollbackService < BetterService::Services::Base
    schema {}

    process_with do |_data|
      { resource: { value: "success" } }
    end
  end

  # Workflow with rollback handlers
  class WorkflowWithRollback < BetterService::Workflows::Base
    with_transaction true

    step :step_one,
         with: SuccessService,
         input: ->(ctx) { { step_name: "one" } },
         rollback: ->(ctx) { RollbackTracker.track(:step_one) }

    step :step_two,
         with: SuccessService,
         input: ->(ctx) { { step_name: "two" } },
         rollback: ->(ctx) { RollbackTracker.track(:step_two) }

    step :failing_step,
         with: FailingService

    step :unreachable,
         with: SuccessService,
         rollback: ->(ctx) { RollbackTracker.track(:unreachable) }
  end

  # Workflow where some steps have no rollback
  class PartialRollbackWorkflow < BetterService::Workflows::Base
    with_transaction true

    step :with_rollback,
         with: SuccessService,
         rollback: ->(ctx) { RollbackTracker.track(:with_rollback) }

    step :without_rollback,
         with: SuccessService

    step :another_with_rollback,
         with: SuccessService,
         rollback: ->(ctx) { RollbackTracker.track(:another_with_rollback) }

    step :failing,
         with: FailingService
  end

  # Workflow where rollback itself fails
  class WorkflowWithFailingRollback < BetterService::Workflows::Base
    with_transaction true

    step :first_step,
         with: SuccessService,
         rollback: ->(ctx) { raise StandardError, "Rollback failed!" }

    step :failing_step,
         with: FailingService
  end

  # Workflow with rollback that accesses context
  class WorkflowWithContextRollback < BetterService::Workflows::Base
    with_transaction true

    step :create_order,
         with: SuccessService,
         input: ->(ctx) { { value: 100 } },
         rollback: ->(ctx) {
           RollbackTracker.track(:create_order)
           ctx.rollback_data = { order_value: ctx.create_order[:value] }
         }

    step :failing_step,
         with: FailingService
  end

  setup do
    @user = User.new(1)
    RollbackTracker.reset!
  end

  # =====================
  # Basic rollback tests
  # =====================

  test "rollback is called when workflow fails" do
    assert_raises(BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError) do
      WorkflowWithRollback.new(@user, params: {}).call
    end

    assert_includes RollbackTracker.rollback_calls, :step_one
    assert_includes RollbackTracker.rollback_calls, :step_two
  end

  test "rollback executes in reverse order" do
    assert_raises(BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError) do
      WorkflowWithRollback.new(@user, params: {}).call
    end

    # Should be step_two first (reverse order), then step_one
    assert_equal [:step_two, :step_one], RollbackTracker.rollback_order
  end

  test "unreachable steps are not rolled back" do
    assert_raises(BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError) do
      WorkflowWithRollback.new(@user, params: {}).call
    end

    assert_not_includes RollbackTracker.rollback_calls, :unreachable
  end

  # =====================
  # Partial rollback tests
  # =====================

  test "only steps with rollback handlers are rolled back" do
    assert_raises(BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError) do
      PartialRollbackWorkflow.new(@user, params: {}).call
    end

    assert_includes RollbackTracker.rollback_calls, :with_rollback
    assert_includes RollbackTracker.rollback_calls, :another_with_rollback
  end

  test "steps without rollback are silently skipped during rollback" do
    # Should not raise any errors about missing rollback
    assert_raises(BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError) do
      PartialRollbackWorkflow.new(@user, params: {}).call
    end

    # Just verify the workflow completed the rollback process
    assert RollbackTracker.rollback_calls.count >= 2
  end

  # =====================
  # Failing rollback tests
  # =====================

  test "failing rollback raises RollbackError" do
    error = assert_raises(BetterService::Errors::Workflowable::Runtime::RollbackError) do
      WorkflowWithFailingRollback.new(@user, params: {}).call
    end

    assert_equal :rollback_failed, error.code
    assert_includes error.message, "Rollback failed"
    assert_includes error.message, "first_step"
  end

  test "failing rollback includes context information" do
    error = assert_raises(BetterService::Errors::Workflowable::Runtime::RollbackError) do
      WorkflowWithFailingRollback.new(@user, params: {}).call
    end

    assert error.context[:workflow].present?
    assert_equal :first_step, error.context[:step]
  end

  test "failing rollback preserves original error" do
    error = assert_raises(BetterService::Errors::Workflowable::Runtime::RollbackError) do
      WorkflowWithFailingRollback.new(@user, params: {}).call
    end

    assert_instance_of StandardError, error.original_error
    assert_equal "Rollback failed!", error.original_error.message
  end

  # =====================
  # Context in rollback tests
  # =====================

  test "rollback has access to context data" do
    workflow = WorkflowWithContextRollback.new(@user, params: {})

    assert_raises(BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError) do
      workflow.call
    end

    # Verify rollback was called
    assert_includes RollbackTracker.rollback_calls, :create_order

    # Verify rollback could access context
    context = workflow.instance_variable_get(:@context)
    assert_equal({ order_value: 100 }, context.rollback_data)
  end

  # =====================
  # No rollback needed tests
  # =====================

  test "successful workflow does not trigger rollback" do
    workflow_class = Class.new(BetterService::Workflows::Base) do
      with_transaction true

      step :step_one,
           with: SuccessService,
           rollback: ->(ctx) { RollbackTracker.track(:step_one) }

      step :step_two,
           with: SuccessService,
           rollback: ->(ctx) { RollbackTracker.track(:step_two) }
    end

    result = workflow_class.new(@user, params: {}).call

    assert result[:success]
    assert_empty RollbackTracker.rollback_calls
  end

  # =====================
  # Multiple failures tests
  # =====================

  test "rollback continues for all steps even with first step having no rollback" do
    workflow_class = Class.new(BetterService::Workflows::Base) do
      with_transaction true

      # First step has no rollback
      step :no_rollback_step,
           with: SuccessService

      # Second step has rollback
      step :with_rollback,
           with: SuccessService,
           rollback: ->(ctx) { RollbackTracker.track(:with_rollback) }

      step :failing,
           with: FailingService
    end

    assert_raises(BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError) do
      workflow_class.new(@user, params: {}).call
    end

    assert_includes RollbackTracker.rollback_calls, :with_rollback
  end

  # =====================
  # Step instance variable tests
  # =====================

  test "executed_steps tracks only executed steps" do
    workflow = WorkflowWithRollback.new(@user, params: {})

    assert_raises(BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError) do
      workflow.call
    end

    executed_steps = workflow.instance_variable_get(:@executed_steps)
    executed_names = executed_steps.map(&:name)

    assert_includes executed_names, :step_one
    assert_includes executed_names, :step_two
    assert_not_includes executed_names, :failing_step
    assert_not_includes executed_names, :unreachable
  end

  # =====================
  # Rollback with branching tests
  # =====================

  test "rollback only affects executed steps, not other branches" do
    workflow_class = Class.new(BetterService::Workflows::Base) do
      with_transaction true

      step :common_step,
           with: SuccessService,
           rollback: ->(ctx) { RollbackTracker.track(:common_step) }

      branch do
        on ->(ctx) { ctx.path == "A" } do
          step :path_a_step,
               with: SuccessService,
               rollback: ->(ctx) { RollbackTracker.track(:path_a_step) }

          step :path_a_fail,
               with: FailingService
        end

        on ->(ctx) { ctx.path == "B" } do
          step :path_b_step,
               with: SuccessService,
               rollback: ->(ctx) { RollbackTracker.track(:path_b_step) }
        end
      end
    end

    workflow = workflow_class.new(@user, params: {})
    workflow.instance_variable_get(:@context).path = "A"

    assert_raises(BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError) do
      workflow.call
    end

    # Common step before branch should be rolled back
    assert_includes RollbackTracker.rollback_calls, :common_step

    # Should NOT rollback path_b_step (different branch)
    assert_not_includes RollbackTracker.rollback_calls, :path_b_step

    # Branch steps execution and rollback depends on implementation
    # The key guarantee is that unused branches are never executed or rolled back
  end
end
