# frozen_string_literal: true

require "test_helper"

class BetterService::Workflows::BranchUnitTest < ActiveSupport::TestCase
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

  # Mock service for testing
  class MockStepService < BetterService::Services::Base
    schema do
      optional(:value).maybe(:integer)
    end

    process_with do |_data|
      { resource: { processed: true, value: params[:value] } }
    end
  end

  class FailingStepService < BetterService::Services::Base
    schema do
      optional(:fail).maybe(:bool)
    end

    process_with do |_data|
      raise StandardError, "Step service failed"
    end
  end

  setup do
    @user = User.new(1)
    @context = BetterService::Workflowable::Context.new(@user)
  end

  # =====================
  # Initialization tests
  # =====================

  test "initializes with condition and name" do
    condition = ->(ctx) { ctx.user.premium? }
    branch = BetterService::Workflows::Branch.new(
      condition: condition,
      name: :premium_path
    )

    assert_equal condition, branch.condition
    assert_equal :premium_path, branch.name
    assert_empty branch.steps
  end

  test "initializes with nil condition for default branch" do
    branch = BetterService::Workflows::Branch.new(condition: nil, name: :default)

    assert_nil branch.condition
    assert branch.default?
  end

  test "steps array is initially empty" do
    branch = BetterService::Workflows::Branch.new

    assert_instance_of Array, branch.steps
    assert_empty branch.steps
  end

  # =====================
  # matches? tests
  # =====================

  test "matches? returns true when condition evaluates to true" do
    @context.should_match = true

    branch = BetterService::Workflows::Branch.new(
      condition: ->(ctx) { ctx.should_match }
    )

    assert branch.matches?(@context)
  end

  test "matches? returns false when condition evaluates to false" do
    @context.should_match = false

    branch = BetterService::Workflows::Branch.new(
      condition: ->(ctx) { ctx.should_match }
    )

    assert_not branch.matches?(@context)
  end

  test "matches? always returns true for default branch (nil condition)" do
    branch = BetterService::Workflows::Branch.new(condition: nil)

    assert branch.matches?(@context)
  end

  test "matches? handles complex conditions" do
    @context.amount = 150
    @context.status = "active"

    branch = BetterService::Workflows::Branch.new(
      condition: ->(ctx) { ctx.amount > 100 && ctx.status == "active" }
    )

    assert branch.matches?(@context)
  end

  test "matches? returns false when condition raises error" do
    branch = BetterService::Workflows::Branch.new(
      condition: ->(ctx) { raise "Condition error" }
    )

    # Should return false and not propagate the error
    assert_not branch.matches?(@context)
  end

  test "matches? works with user object in context" do
    premium_user = User.new(1, premium: true)
    @context = BetterService::Workflowable::Context.new(premium_user)

    branch = BetterService::Workflows::Branch.new(
      condition: ->(ctx) { ctx.user.premium? }
    )

    assert branch.matches?(@context)
  end

  # =====================
  # add_step tests
  # =====================

  test "add_step adds a step to the branch" do
    branch = BetterService::Workflows::Branch.new(name: :test_branch)

    step = BetterService::Workflowable::Step.new(
      name: :test_step,
      service_class: MockStepService
    )

    branch.add_step(step)

    assert_equal 1, branch.steps.count
    assert_equal step, branch.steps.first
  end

  test "add_step maintains order of steps" do
    branch = BetterService::Workflows::Branch.new(name: :test_branch)

    step1 = BetterService::Workflowable::Step.new(name: :step1, service_class: MockStepService)
    step2 = BetterService::Workflowable::Step.new(name: :step2, service_class: MockStepService)
    step3 = BetterService::Workflowable::Step.new(name: :step3, service_class: MockStepService)

    branch.add_step(step1)
    branch.add_step(step2)
    branch.add_step(step3)

    assert_equal [:step1, :step2, :step3], branch.steps.map(&:name)
  end

  test "add_step returns updated steps array" do
    branch = BetterService::Workflows::Branch.new

    step = BetterService::Workflowable::Step.new(name: :test, service_class: MockStepService)
    result = branch.add_step(step)

    assert_instance_of Array, result
    assert_includes result, step
  end

  # =====================
  # execute tests
  # =====================

  test "execute runs all steps in branch" do
    branch = BetterService::Workflows::Branch.new(name: :test_branch)

    step1 = BetterService::Workflowable::Step.new(name: :step1, service_class: MockStepService)
    step2 = BetterService::Workflowable::Step.new(name: :step2, service_class: MockStepService)

    branch.add_step(step1)
    branch.add_step(step2)

    executed_steps = branch.execute(@context, @user, {})

    assert_equal 2, executed_steps.count
    assert_equal [:step1, :step2], executed_steps.map(&:name)
  end

  test "execute stores step results in context" do
    branch = BetterService::Workflows::Branch.new(name: :test_branch)

    step = BetterService::Workflowable::Step.new(
      name: :process_step,
      service_class: MockStepService,
      input: ->(ctx) { { value: 42 } }
    )

    branch.add_step(step)
    branch.execute(@context, @user, {})

    assert_equal({ processed: true, value: 42 }, @context.process_step)
  end

  test "execute returns empty array when no steps defined" do
    branch = BetterService::Workflows::Branch.new(name: :empty_branch)

    executed_steps = branch.execute(@context, @user, {})

    assert_empty executed_steps
  end

  test "execute skips steps with false conditions" do
    branch = BetterService::Workflows::Branch.new(name: :test_branch)
    @context.should_run = false

    step = BetterService::Workflowable::Step.new(
      name: :conditional_step,
      service_class: MockStepService,
      condition: ->(ctx) { ctx.should_run }
    )

    branch.add_step(step)
    executed_steps = branch.execute(@context, @user, {})

    assert_empty executed_steps
  end

  test "execute raises error when required step fails" do
    branch = BetterService::Workflows::Branch.new(name: :test_branch)

    step = BetterService::Workflowable::Step.new(
      name: :failing_step,
      service_class: FailingStepService,
      optional: false
    )

    branch.add_step(step)

    # Services wrap exceptions in ExecutionError, which propagates up
    error = assert_raises(BetterService::Errors::Runtime::ExecutionError) do
      branch.execute(@context, @user, {})
    end

    assert_equal :execution_error, error.code
    assert_includes error.message, "Step service failed"
  end

  test "execute continues when optional step fails" do
    branch = BetterService::Workflows::Branch.new(name: :test_branch)

    optional_step = BetterService::Workflowable::Step.new(
      name: :optional_step,
      service_class: FailingStepService,
      optional: true
    )

    next_step = BetterService::Workflowable::Step.new(
      name: :next_step,
      service_class: MockStepService
    )

    branch.add_step(optional_step)
    branch.add_step(next_step)

    executed_steps = branch.execute(@context, @user, {})

    # Should have executed next_step (optional failure doesn't add to executed)
    assert_equal [:next_step], executed_steps.map(&:name)
  end

  # =====================
  # default? tests
  # =====================

  test "default? returns true when condition is nil" do
    branch = BetterService::Workflows::Branch.new(condition: nil)

    assert branch.default?
  end

  test "default? returns false when condition is present" do
    branch = BetterService::Workflows::Branch.new(
      condition: ->(ctx) { true }
    )

    assert_not branch.default?
  end

  # =====================
  # inspect tests
  # =====================

  test "inspect returns informative string" do
    branch = BetterService::Workflows::Branch.new(
      condition: ->(ctx) { true },
      name: :my_branch
    )

    step = BetterService::Workflowable::Step.new(name: :step1, service_class: MockStepService)
    branch.add_step(step)

    inspect_string = branch.inspect

    assert_includes inspect_string, "BetterService::Workflows::Branch"
    assert_includes inspect_string, "name=:my_branch"
    assert_includes inspect_string, "condition=present"
    assert_includes inspect_string, "steps=1"
  end

  test "inspect shows nil condition for default branch" do
    branch = BetterService::Workflows::Branch.new(condition: nil, name: :default)

    inspect_string = branch.inspect

    assert_includes inspect_string, "condition=nil"
  end
end
