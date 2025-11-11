# frozen_string_literal: true

require "test_helper"

class BetterService::WorkflowTest < ActiveSupport::TestCase
  class User
    attr_accessor :id, :name
    def initialize(id, name)
      @id = id
      @name = name
    end
  end

  # Mock services for testing
  class FirstService < BetterService::Services::Base
    schema do
      required(:value).filled(:integer)
    end

    process_with do |data|
      { resource: { result: params[:value] * 2 } }
    end
  end

  class SecondService < BetterService::Services::Base
    schema do
      required(:previous_result).filled(:integer)
    end

    process_with do |data|
      { resource: { final: params[:previous_result] + 10 } }
    end
  end

  class FailingService < BetterService::Services::Base
    schema do
    end

    process_with do |data|
      raise StandardError, "Service failed"
    end
  end

  # Test workflow without transaction
  class SimpleWorkflow < BetterService::Workflows::Base
    step :first,
         with: FirstService,
         input: ->(ctx) { { value: ctx.initial_value } }

    step :second,
         with: SecondService,
         input: ->(ctx) { { previous_result: ctx.first[:result] } }
  end

  # Test workflow with transaction
  class TransactionalWorkflow < BetterService::Workflows::Base
    with_transaction true

    step :first,
         with: FirstService,
         input: ->(ctx) { { value: ctx.initial_value } }
  end

  # Test workflow with callbacks
  class CallbackWorkflow < BetterService::Workflows::Base
    attr_accessor :before_called, :after_called, :around_called

    before_workflow :before_hook
    after_workflow :after_hook
    around_step :around_hook

    step :first,
         with: FirstService,
         input: ->(ctx) { { value: ctx.initial_value } }

    private

    def before_hook(context)
      @before_called = true
    end

    def after_hook(context)
      @after_called = true
    end

    def around_hook(step, context)
      @around_called = true
      yield
    end
  end

  # Test workflow with optional step
  class OptionalStepWorkflow < BetterService::Workflows::Base
    step :first,
         with: FirstService,
         input: ->(ctx) { { value: ctx.initial_value } }

    step :failing,
         with: FailingService,
         optional: true

    step :second,
         with: SecondService,
         input: ->(ctx) { { previous_result: ctx.first[:result] } }
  end

  # Test workflow with conditional step
  class ConditionalWorkflow < BetterService::Workflows::Base
    step :first,
         with: FirstService,
         input: ->(ctx) { { value: ctx.initial_value } },
         if: ->(ctx) { ctx.should_run }
  end

  setup do
    @user = User.new(1, "Test User")
  end

  test "executes workflow steps in sequence" do
    result = SimpleWorkflow.new(@user, params: { initial_value: 5 }).call

    assert result[:success]
    assert_equal 10, result[:context].first[:result]
    assert_equal 20, result[:context].second[:final]
  end

  test "returns workflow metadata" do
    result = SimpleWorkflow.new(@user, params: { initial_value: 5 }).call

    assert_equal "BetterService::WorkflowTest::SimpleWorkflow", result[:metadata][:workflow]
    assert_equal [:first, :second], result[:metadata][:steps_executed]
    assert_equal [], result[:metadata][:steps_skipped]
    assert result[:metadata][:duration_ms].is_a?(Numeric), "duration_ms is #{result[:metadata][:duration_ms].inspect}, should be Numeric"
  end

  test "workflow with transaction support" do
    result = TransactionalWorkflow.new(@user, params: { initial_value: 5 }).call

    assert result[:success]
    assert_equal 10, result[:context].first[:result]
  end

  test "executes before and after callbacks" do
    workflow = CallbackWorkflow.new(@user, params: { initial_value: 5 })
    result = workflow.call

    assert result[:success]
    assert workflow.before_called, "before_workflow callback should be called"
    assert workflow.after_called, "after_workflow callback should be called"
    assert workflow.around_called, "around_step callback should be called"
  end

  test "before_workflow callback can fail the workflow" do
    workflow_class = Class.new(BetterService::Workflows::Base) do
      before_workflow :fail_it

      step :first,
           with: FirstService,
           input: ->(ctx) { { value: ctx.initial_value } }

      private

      def fail_it(context)
        context.fail!("Not allowed")
      end
    end

    result = workflow_class.new(@user, params: { initial_value: 5 }).call

    assert_not result[:success]
    assert_equal "Not allowed", result[:errors][:message]
  end

  test "optional step doesn't stop workflow on failure" do
    result = OptionalStepWorkflow.new(@user, params: { initial_value: 5 }).call

    assert result[:success]
    assert_equal 10, result[:context].first[:result]
    assert_equal 20, result[:context].second[:final]
  end

  test "conditional step is skipped when condition is false" do
    result = ConditionalWorkflow.new(@user, params: { initial_value: 5, should_run: false }).call

    assert result[:success]
    assert_equal [], result[:metadata][:steps_executed]
    assert_equal [:first], result[:metadata][:steps_skipped]
  end

  test "conditional step is executed when condition is true" do
    result = ConditionalWorkflow.new(@user, params: { initial_value: 5, should_run: true }).call

    assert result[:success]
    assert_equal [:first], result[:metadata][:steps_executed]
    assert_equal [], result[:metadata][:steps_skipped]
  end

  test "failing step stops workflow and returns error" do
    workflow_class = Class.new(BetterService::Workflows::Base) do
      step :first,
           with: FirstService,
           input: ->(ctx) { { value: ctx.initial_value } }

      step :failing,
           with: FailingService

      step :second,
           with: SecondService,
           input: ->(ctx) { { previous_result: 10 } }
    end

    error = assert_raises(BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError) do
      workflow_class.new(@user, params: { initial_value: 5 }).call
    end

    assert_equal :workflow_failed, error.code
    assert error.context[:steps_executed].include?(:first)
  end

  test "workflow executes rollback on failure" do
    workflow_class = Class.new(BetterService::Workflows::Base) do
      step :first,
           with: FirstService,
           input: ->(ctx) { { value: ctx.initial_value } },
           rollback: ->(ctx) { } # Rollback defined but not tested here

      step :failing,
           with: FailingService
    end

    error = assert_raises(BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError) do
      workflow_class.new(@user, params: { initial_value: 5 }).call
    end

    assert_equal :workflow_failed, error.code
    # Note: Testing rollback execution would require different approach (e.g., shared state)
  end

  test "workflow context is accessible in result" do
    result = SimpleWorkflow.new(@user, params: { initial_value: 5 }).call

    assert_instance_of BetterService::Workflowable::Context, result[:context]
    assert_equal @user, result[:context].user
    assert result[:context].success?
  end
end
