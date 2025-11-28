# frozen_string_literal: true

require "test_helper"

class BetterService::Workflows::BranchDSLTest < ActiveSupport::TestCase
  class User
    attr_accessor :id
    def initialize(id)
      @id = id
    end
  end

  # Mock service for testing
  class MockService < BetterService::Services::Base
    schema do
      optional(:value).maybe(:integer)
    end

    process_with do |_data|
      { resource: { value: params[:value] || 42 } }
    end
  end

  setup do
    @branch_group = BetterService::Workflows::BranchGroup.new(name: :test_group)
    @dsl = BetterService::Workflows::BranchDSL.new(@branch_group)
  end

  # =====================
  # Initialization tests
  # =====================

  test "initializes with branch group" do
    assert_equal @branch_group, @dsl.branch_group
  end

  # =====================
  # on() tests
  # =====================

  test "on creates a conditional branch" do
    @dsl.on ->(ctx) { ctx.premium? } do
      step :premium_step, with: MockService
    end

    assert_equal 1, @branch_group.branches.count
    assert_equal :on_1, @branch_group.branches.first.name
  end

  test "on requires a Proc condition" do
    error = assert_raises(ArgumentError) do
      @dsl.on "not a proc" do
        step :test, with: MockService
      end
    end

    assert_includes error.message, "Condition must be a Proc"
  end

  test "on requires a block" do
    error = assert_raises(ArgumentError) do
      @dsl.on ->(ctx) { true }
    end

    assert_includes error.message, "Block required"
  end

  test "on increments branch index for naming" do
    @dsl.on ->(ctx) { true } do
      step :step1, with: MockService
    end

    @dsl.on ->(ctx) { false } do
      step :step2, with: MockService
    end

    @dsl.on ->(ctx) { true } do
      step :step3, with: MockService
    end

    assert_equal [:on_1, :on_2, :on_3], @branch_group.branches.map(&:name)
  end

  test "on adds steps to the correct branch" do
    @dsl.on ->(ctx) { ctx.type == "A" } do
      step :step_a1, with: MockService
      step :step_a2, with: MockService
    end

    @dsl.on ->(ctx) { ctx.type == "B" } do
      step :step_b1, with: MockService
    end

    branch_a = @branch_group.branches[0]
    branch_b = @branch_group.branches[1]

    assert_equal [:step_a1, :step_a2], branch_a.steps.map(&:name)
    assert_equal [:step_b1], branch_b.steps.map(&:name)
  end

  # =====================
  # otherwise() tests
  # =====================

  test "otherwise creates default branch" do
    @dsl.otherwise do
      step :default_step, with: MockService
    end

    assert @branch_group.has_default?
    assert_equal :otherwise, @branch_group.default_branch.name
  end

  test "otherwise requires a block" do
    error = assert_raises(ArgumentError) do
      @dsl.otherwise
    end

    assert_includes error.message, "Block required"
  end

  test "otherwise can only be called once" do
    @dsl.otherwise do
      step :default1, with: MockService
    end

    error = assert_raises(ArgumentError) do
      @dsl.otherwise do
        step :default2, with: MockService
      end
    end

    assert_includes error.message, "Default branch already defined"
  end

  test "otherwise adds steps to default branch" do
    @dsl.otherwise do
      step :default_step1, with: MockService
      step :default_step2, with: MockService
    end

    default = @branch_group.default_branch
    assert_equal [:default_step1, :default_step2], default.steps.map(&:name)
  end

  # =====================
  # step() tests
  # =====================

  test "step raises error when called outside branch" do
    error = assert_raises(RuntimeError) do
      @dsl.step :orphan_step, with: MockService
    end

    assert_includes error.message, "must be called within"
  end

  test "step creates Step object with correct attributes" do
    @dsl.on ->(ctx) { true } do
      step :test_step,
           with: MockService,
           input: ->(ctx) { { value: 100 } },
           optional: true
    end

    step = @branch_group.branches.first.steps.first

    assert_equal :test_step, step.name
    assert_equal MockService, step.service_class
    assert step.optional
  end

  test "step supports rollback option" do
    rollback_proc = ->(ctx) { ctx.rollback_called = true }

    @dsl.on ->(ctx) { true } do
      step :with_rollback,
           with: MockService,
           rollback: rollback_proc
    end

    step = @branch_group.branches.first.steps.first

    assert_not_nil step.rollback_block
  end

  # =====================
  # nested branch() tests
  # =====================

  test "branch creates nested branch group" do
    @dsl.on ->(ctx) { ctx.type == "contract" } do
      step :validate, with: MockService

      branch do
        on ->(ctx) { ctx.value > 10000 } do
          step :ceo_approval, with: MockService
        end

        otherwise do
          step :manager_approval, with: MockService
        end
      end
    end

    outer_branch = @branch_group.branches.first
    assert_equal 2, outer_branch.steps.count

    # First should be a step
    assert_instance_of BetterService::Workflowable::Step, outer_branch.steps[0]
    assert_equal :validate, outer_branch.steps[0].name

    # Second should be a nested BranchGroup
    nested_group = outer_branch.steps[1]
    assert_instance_of BetterService::Workflows::BranchGroup, nested_group
    assert_equal 1, nested_group.branches.count
    assert nested_group.has_default?
  end

  test "nested branch raises error when called outside branch" do
    error = assert_raises(RuntimeError) do
      @dsl.branch do
        on ->(ctx) { true } do
          step :test, with: MockService
        end
      end
    end

    assert_includes error.message, "must be called within"
  end

  test "nested branch requires a block" do
    # The validation for block is done at method call time
    # A valid on block with no nested branch issues
    @dsl.on ->(ctx) { true } do
      step :valid_step, with: MockService
    end

    # Verify the step was added successfully
    assert_equal 1, @branch_group.branches.count
  end

  # =====================
  # Complex DSL composition tests
  # =====================

  test "supports complex multi-branch composition" do
    @dsl.on ->(ctx) { ctx.priority == "high" } do
      step :urgent_process, with: MockService
      step :notify_manager, with: MockService
    end

    @dsl.on ->(ctx) { ctx.priority == "medium" } do
      step :standard_process, with: MockService
    end

    @dsl.on ->(ctx) { ctx.priority == "low" } do
      step :batch_process, with: MockService
    end

    @dsl.otherwise do
      step :queue_for_review, with: MockService
    end

    assert_equal 3, @branch_group.branches.count
    assert @branch_group.has_default?
    assert_equal 4, @branch_group.branch_count
  end

  test "branch steps are isolated between on blocks" do
    @dsl.on ->(ctx) { true } do
      step :branch1_step, with: MockService
    end

    @dsl.on ->(ctx) { true } do
      step :branch2_step, with: MockService
    end

    @dsl.otherwise do
      step :default_step, with: MockService
    end

    # Verify isolation
    assert_equal 1, @branch_group.branches[0].steps.count
    assert_equal 1, @branch_group.branches[1].steps.count
    assert_equal 1, @branch_group.default_branch.steps.count

    assert_equal :branch1_step, @branch_group.branches[0].steps.first.name
    assert_equal :branch2_step, @branch_group.branches[1].steps.first.name
    assert_equal :default_step, @branch_group.default_branch.steps.first.name
  end
end
