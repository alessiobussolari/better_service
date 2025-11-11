# frozen_string_literal: true

require "test_helper"

class BetterService::Workflowable::StepTest < ActiveSupport::TestCase
  class User
    attr_accessor :id, :name
    def initialize(id, name)
      @id = id
      @name = name
    end
  end

  # Mock service for testing
  class MockService < BetterService::Services::Base
    schema do
      optional(:value).maybe(:integer)
    end

    process_with do |data|
      { resource: { value: params[:value] || 42 } }
    end
  end

  class FailingService < BetterService::Services::Base
    schema do
      required(:value).filled(:integer)
    end

    process_with do |data|
      raise StandardError, "Service failed"
    end
  end

  setup do
    @user = User.new(1, "Test User")
    @context = BetterService::Workflowable::Context.new(@user)
  end

  test "executes service and stores result in context" do
    step = BetterService::Workflowable::Step.new(
      name: :test_step,
      service_class: MockService
    )

    result = step.call(@context, @user)

    assert result[:success]
    assert_equal({ value: 42 }, @context.test_step)
  end

  test "uses input mapper to build service params" do
    @context.amount = 100

    step = BetterService::Workflowable::Step.new(
      name: :test_step,
      service_class: MockService,
      input: ->(ctx) { { value: ctx.amount * 2 } }
    )

    result = step.call(@context, @user)

    assert result[:success]
    assert_equal({ value: 200 }, @context.test_step)
  end

  test "skips step when condition returns false" do
    @context.should_run = false

    step = BetterService::Workflowable::Step.new(
      name: :test_step,
      service_class: MockService,
      condition: ->(ctx) { ctx.should_run }
    )

    result = step.call(@context, @user)

    assert result[:success]
    assert result[:skipped]
    assert_nil @context.get(:test_step)
  end

  test "executes step when condition returns true" do
    @context.should_run = true

    step = BetterService::Workflowable::Step.new(
      name: :test_step,
      service_class: MockService,
      condition: ->(ctx) { ctx.should_run }
    )

    result = step.call(@context, @user)

    assert result[:success]
    assert_not result[:skipped]
    assert_equal({ value: 42 }, @context.test_step)
  end

  test "continues on failure when step is optional" do
    step = BetterService::Workflowable::Step.new(
      name: :failing_step,
      service_class: FailingService,
      optional: true
    )

    result = step.call(@context, @user, {})

    assert result[:success], "Optional step should not fail the workflow"
    assert result[:optional_failure]
    assert @context.get(:failing_step_error).present?
  end

  test "returns failure when required step fails" do
    step = BetterService::Workflowable::Step.new(
      name: :failing_step,
      service_class: FailingService,
      optional: false
    )

    error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
      step.call(@context, @user, {})
    end

    assert_equal :validation_failed, error.code
  end

  test "executes rollback block when provided" do
    rollback_executed = false

    step = BetterService::Workflowable::Step.new(
      name: :test_step,
      service_class: MockService,
      rollback: ->(ctx) { rollback_executed = true }
    )

    step.rollback(@context)

    assert rollback_executed
  end

  test "rollback propagates errors to workflow" do
    step = BetterService::Workflowable::Step.new(
      name: :test_step,
      service_class: MockService,
      rollback: ->(ctx) { raise "Rollback error" }
    )

    # Rollback errors are propagated (will be wrapped by workflow)
    assert_raises(RuntimeError, "Rollback error") do
      step.rollback(@context)
    end
  end
end
