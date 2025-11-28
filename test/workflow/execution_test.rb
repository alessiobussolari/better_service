# frozen_string_literal: true

require "test_helper"

class BetterService::Workflows::ExecutionTest < ActiveSupport::TestCase
  class User
    attr_accessor :id, :premium
    def initialize(id, premium: false)
      @id = id
      @premium = premium
    end

    def premium?
      @premium
    end
  end

  # Mock services for testing
  class SuccessService < BetterService::Services::Base
    schema do
      optional(:value).maybe(:integer)
    end

    process_with do |_data|
      { resource: { value: params[:value] || 42 } }
    end
  end

  class FailingService < BetterService::Services::Base
    schema do
      optional(:should_fail).maybe(:bool)
    end

    process_with do |_data|
      raise StandardError, "Service intentionally failed"
    end
  end

  class TrackingService < BetterService::Services::Base
    schema do
      optional(:step_name).maybe(:string)
    end

    process_with do |_data|
      # Track execution in a class variable for testing
      @@executed_steps ||= []
      @@executed_steps << params[:step_name]
      { resource: { step: params[:step_name] } }
    end

    def self.executed_steps
      @@executed_steps ||= []
    end

    def self.reset_tracking!
      @@executed_steps = []
    end
  end

  # Test workflow with Execution module
  class LinearWorkflow < BetterService::Workflows::Base
    step :step_one,
         with: SuccessService,
         input: ->(ctx) { { value: 1 } }

    step :step_two,
         with: SuccessService,
         input: ->(ctx) { { value: 2 } }

    step :step_three,
         with: SuccessService,
         input: ->(ctx) { { value: 3 } }
  end

  class WorkflowWithOptionalStep < BetterService::Workflows::Base
    step :required_step,
         with: SuccessService

    step :optional_step,
         with: FailingService,
         optional: true

    step :final_step,
         with: SuccessService
  end

  class WorkflowWithConditionalStep < BetterService::Workflows::Base
    step :always_runs,
         with: SuccessService

    step :conditional_step,
         with: SuccessService,
         if: ->(ctx) { ctx.should_run }

    step :final_step,
         with: SuccessService
  end

  class WorkflowWithFailingStep < BetterService::Workflows::Base
    step :first_step,
         with: SuccessService

    step :failing_step,
         with: FailingService

    step :unreachable_step,
         with: SuccessService
  end

  class WorkflowWithBranching < BetterService::Workflows::Base
    step :validate,
         with: SuccessService

    branch do
      on ->(ctx) { ctx.path == "A" } do
        step :path_a_step,
             with: SuccessService,
             input: ->(ctx) { { value: 100 } }
      end

      on ->(ctx) { ctx.path == "B" } do
        step :path_b_step,
             with: SuccessService,
             input: ->(ctx) { { value: 200 } }
      end

      otherwise do
        step :default_step,
             with: SuccessService,
             input: ->(ctx) { { value: 0 } }
      end
    end

    step :finalize,
         with: SuccessService
  end

  setup do
    @user = User.new(1)
    TrackingService.reset_tracking!
  end

  # =====================
  # Linear execution tests
  # =====================

  test "executes all steps in order" do
    result = LinearWorkflow.new(@user, params: {}).call

    assert result[:success]
    assert_equal [:step_one, :step_two, :step_three], result[:metadata][:steps_executed]
  end

  test "stores step results in context" do
    result = LinearWorkflow.new(@user, params: {}).call

    assert_equal({ value: 1 }, result[:context].step_one)
    assert_equal({ value: 2 }, result[:context].step_two)
    assert_equal({ value: 3 }, result[:context].step_three)
  end

  test "calculates workflow duration" do
    result = LinearWorkflow.new(@user, params: {}).call

    assert result[:metadata][:duration_ms].is_a?(Numeric)
    assert result[:metadata][:duration_ms] >= 0
  end

  # =====================
  # Optional step tests
  # =====================

  test "continues workflow when optional step fails" do
    result = WorkflowWithOptionalStep.new(@user, params: {}).call

    assert result[:success]
    assert_includes result[:metadata][:steps_executed], :required_step
    assert_includes result[:metadata][:steps_executed], :final_step
    # Optional step is executed (even if it fails, the step itself runs)
    # The workflow continues to final_step without stopping
    assert_includes result[:metadata][:steps_executed], :optional_step
  end

  # =====================
  # Conditional step tests
  # =====================

  test "executes conditional step when condition is true" do
    workflow = WorkflowWithConditionalStep.new(@user, params: {})
    workflow.instance_variable_get(:@context).should_run = true

    result = workflow.call

    assert result[:success]
    assert_includes result[:metadata][:steps_executed], :conditional_step
    assert_empty result[:metadata][:steps_skipped]
  end

  test "skips conditional step when condition is false" do
    workflow = WorkflowWithConditionalStep.new(@user, params: {})
    workflow.instance_variable_get(:@context).should_run = false

    result = workflow.call

    assert result[:success]
    assert_not_includes result[:metadata][:steps_executed], :conditional_step
    assert_includes result[:metadata][:steps_skipped], :conditional_step
  end

  # =====================
  # Step failure tests
  # =====================

  test "raises WorkflowExecutionError when required step fails" do
    error = assert_raises(BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError) do
      WorkflowWithFailingStep.new(@user, params: {}).call
    end

    assert_equal :workflow_failed, error.code
    assert_includes error.message, "Service intentionally failed"
  end

  test "does not execute steps after failure" do
    workflow = WorkflowWithFailingStep.new(@user, params: {})

    assert_raises(BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError) do
      workflow.call
    end

    # Verify first_step was executed before failure
    executed_names = workflow.instance_variable_get(:@executed_steps).map(&:name)
    assert_includes executed_names, :first_step
    assert_not_includes executed_names, :unreachable_step
  end

  # =====================
  # Branching execution tests
  # =====================

  test "executes correct branch based on condition" do
    workflow = WorkflowWithBranching.new(@user, params: {})
    workflow.instance_variable_get(:@context).path = "A"

    result = workflow.call

    assert result[:success]
    assert_includes result[:metadata][:steps_executed], :path_a_step
    assert_not_includes result[:metadata][:steps_executed], :path_b_step
    assert_not_includes result[:metadata][:steps_executed], :default_step
  end

  test "executes otherwise branch when no condition matches" do
    workflow = WorkflowWithBranching.new(@user, params: {})
    workflow.instance_variable_get(:@context).path = "UNKNOWN"

    result = workflow.call

    assert result[:success]
    assert_includes result[:metadata][:steps_executed], :default_step
    assert_not_includes result[:metadata][:steps_executed], :path_a_step
    assert_not_includes result[:metadata][:steps_executed], :path_b_step
  end

  test "tracks branch decisions in metadata" do
    workflow = WorkflowWithBranching.new(@user, params: {})
    workflow.instance_variable_get(:@context).path = "B"

    result = workflow.call

    assert result[:metadata][:branches_taken].present?
    assert_includes result[:metadata][:branches_taken].first, "on_2"
  end

  test "executes steps before and after branch" do
    workflow = WorkflowWithBranching.new(@user, params: {})
    workflow.instance_variable_get(:@context).path = "A"

    result = workflow.call

    steps = result[:metadata][:steps_executed]
    assert_equal :validate, steps.first
    assert_equal :finalize, steps.last
  end

  # =====================
  # Error handling tests
  # =====================

  test "wraps unexpected errors in WorkflowExecutionError" do
    # Create a workflow that raises an unexpected error
    workflow_class = Class.new(BetterService::Workflows::Base) do
      step :problematic,
           with: Class.new(BetterService::Services::Base) {
             schema {}
             process_with { raise NoMethodError, "Unexpected error" }
           }
    end

    error = assert_raises(BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError) do
      workflow_class.new(@user, params: {}).call
    end

    assert_equal :workflow_failed, error.code
    # The original error is wrapped in ExecutionError by the service layer
    assert_instance_of BetterService::Errors::Runtime::ExecutionError, error.original_error
    assert_includes error.message, "Unexpected error"
  end
end
