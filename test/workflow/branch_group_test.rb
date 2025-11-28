# frozen_string_literal: true

require "test_helper"

class BetterService::Workflows::BranchGroupTest < ActiveSupport::TestCase
  class User
    attr_accessor :id, :account_type
    def initialize(id, account_type: "basic")
      @id = id
      @account_type = account_type
    end

    def premium?
      @account_type == "premium"
    end
  end

  # Mock service for testing
  class MockService < BetterService::Services::Base
    schema do
      optional(:path).maybe(:string)
    end

    process_with do |_data|
      { resource: { path: params[:path] || "default" } }
    end
  end

  setup do
    @user = User.new(1)
    @context = BetterService::Workflowable::Context.new(@user)
  end

  # =====================
  # Initialization tests
  # =====================

  test "initializes with empty branches and no default" do
    group = BetterService::Workflows::BranchGroup.new(name: :test_group)

    assert_equal :test_group, group.name
    assert_empty group.branches
    assert_nil group.default_branch
  end

  test "initializes without name" do
    group = BetterService::Workflows::BranchGroup.new

    assert_nil group.name
  end

  # =====================
  # add_branch tests
  # =====================

  test "add_branch creates and returns a new branch" do
    group = BetterService::Workflows::BranchGroup.new(name: :test_group)

    condition = ->(ctx) { ctx.user.premium? }
    branch = group.add_branch(condition: condition, name: :premium_path)

    assert_instance_of BetterService::Workflows::Branch, branch
    assert_equal condition, branch.condition
    assert_equal :premium_path, branch.name
  end

  test "add_branch adds branch to branches array" do
    group = BetterService::Workflows::BranchGroup.new

    group.add_branch(condition: ->(ctx) { true }, name: :first)
    group.add_branch(condition: ->(ctx) { false }, name: :second)

    assert_equal 2, group.branches.count
    assert_equal [:first, :second], group.branches.map(&:name)
  end

  # =====================
  # set_default tests
  # =====================

  test "set_default creates default branch" do
    group = BetterService::Workflows::BranchGroup.new

    default = group.set_default(name: :fallback)

    assert_instance_of BetterService::Workflows::Branch, default
    assert_nil default.condition
    assert_equal :fallback, default.name
    assert_equal default, group.default_branch
  end

  test "set_default uses :otherwise as default name" do
    group = BetterService::Workflows::BranchGroup.new

    default = group.set_default

    assert_equal :otherwise, default.name
  end

  # =====================
  # select_branch tests
  # =====================

  test "select_branch returns first matching branch" do
    group = BetterService::Workflows::BranchGroup.new
    @context.value = 100

    branch1 = group.add_branch(
      condition: ->(ctx) { ctx.value > 200 },
      name: :high
    )
    branch2 = group.add_branch(
      condition: ->(ctx) { ctx.value > 50 },
      name: :medium
    )
    branch3 = group.add_branch(
      condition: ->(ctx) { ctx.value > 10 },
      name: :low
    )

    selected = group.select_branch(@context)

    assert_equal branch2, selected
    assert_equal :medium, selected.name
  end

  test "select_branch returns default when no condition matches" do
    group = BetterService::Workflows::BranchGroup.new
    @context.value = 5

    group.add_branch(
      condition: ->(ctx) { ctx.value > 100 },
      name: :high
    )
    default = group.set_default(name: :fallback)

    selected = group.select_branch(@context)

    assert_equal default, selected
  end

  test "select_branch returns nil when no match and no default" do
    group = BetterService::Workflows::BranchGroup.new
    @context.value = 5

    group.add_branch(
      condition: ->(ctx) { ctx.value > 100 },
      name: :high
    )

    selected = group.select_branch(@context)

    assert_nil selected
  end

  test "select_branch evaluates conditions in order" do
    group = BetterService::Workflows::BranchGroup.new
    @context.type = "A"

    # Both conditions match, but first should win
    first = group.add_branch(
      condition: ->(ctx) { ctx.type == "A" },
      name: :first
    )
    group.add_branch(
      condition: ->(ctx) { ctx.type == "A" },
      name: :second
    )

    selected = group.select_branch(@context)

    assert_equal first, selected
  end

  # =====================
  # call tests
  # =====================

  test "call executes matching branch steps" do
    group = BetterService::Workflows::BranchGroup.new(name: :payment_routing)
    @context.payment_type = "card"

    card_branch = group.add_branch(
      condition: ->(ctx) { ctx.payment_type == "card" },
      name: :card_path
    )
    card_branch.add_step(
      BetterService::Workflowable::Step.new(
        name: :process_card,
        service_class: MockService,
        input: ->(ctx) { { path: "card" } }
      )
    )

    paypal_branch = group.add_branch(
      condition: ->(ctx) { ctx.payment_type == "paypal" },
      name: :paypal_path
    )
    paypal_branch.add_step(
      BetterService::Workflowable::Step.new(
        name: :process_paypal,
        service_class: MockService,
        input: ->(ctx) { { path: "paypal" } }
      )
    )

    result = group.call(@context, @user, {})

    assert_equal [:process_card], result[:executed_steps].map(&:name)
    assert_equal card_branch, result[:branch_taken]
    assert_includes result[:branch_decisions], "payment_routing:card_path"
  end

  test "call raises InvalidConfigurationError when no branch matches" do
    group = BetterService::Workflows::BranchGroup.new(name: :test_group)
    @context.value = 0

    group.add_branch(
      condition: ->(ctx) { ctx.value > 100 },
      name: :high
    )

    error = assert_raises(BetterService::Errors::Configuration::InvalidConfigurationError) do
      group.call(@context, @user, {})
    end

    assert_equal :configuration_error, error.code
    assert_includes error.message, "No matching branch"
    assert_equal :test_group, error.context[:branch_group]
    assert_equal 1, error.context[:branches_count]
    assert_equal false, error.context[:has_default]
  end

  test "call returns branch decisions for tracking" do
    group = BetterService::Workflows::BranchGroup.new(name: :routing)
    @context.tier = "gold"

    branch = group.add_branch(
      condition: ->(ctx) { ctx.tier == "gold" },
      name: :gold_path
    )

    result = group.call(@context, @user, {})

    assert_includes result[:branch_decisions], "routing:gold_path"
    assert_not result[:skipped]
  end

  test "call executes default branch when no condition matches" do
    group = BetterService::Workflows::BranchGroup.new(name: :test)
    @context.value = 0

    group.add_branch(
      condition: ->(ctx) { ctx.value > 100 },
      name: :high
    )

    default = group.set_default
    default.add_step(
      BetterService::Workflowable::Step.new(
        name: :default_action,
        service_class: MockService
      )
    )

    result = group.call(@context, @user, {})

    assert_equal [:default_action], result[:executed_steps].map(&:name)
    assert_includes result[:branch_decisions], "test:otherwise"
  end

  # =====================
  # branch_count tests
  # =====================

  test "branch_count returns count of conditional branches" do
    group = BetterService::Workflows::BranchGroup.new

    group.add_branch(condition: ->(ctx) { true }, name: :a)
    group.add_branch(condition: ->(ctx) { true }, name: :b)

    assert_equal 2, group.branch_count
  end

  test "branch_count includes default branch in count" do
    group = BetterService::Workflows::BranchGroup.new

    group.add_branch(condition: ->(ctx) { true }, name: :a)
    group.set_default

    assert_equal 2, group.branch_count
  end

  test "branch_count returns 0 for empty group" do
    group = BetterService::Workflows::BranchGroup.new

    assert_equal 0, group.branch_count
  end

  # =====================
  # has_default? tests
  # =====================

  test "has_default? returns false when no default set" do
    group = BetterService::Workflows::BranchGroup.new

    assert_not group.has_default?
  end

  test "has_default? returns true when default is set" do
    group = BetterService::Workflows::BranchGroup.new
    group.set_default

    assert group.has_default?
  end

  # =====================
  # inspect tests
  # =====================

  test "inspect returns informative string" do
    group = BetterService::Workflows::BranchGroup.new(name: :my_group)

    group.add_branch(condition: ->(ctx) { true }, name: :a)
    group.add_branch(condition: ->(ctx) { false }, name: :b)
    group.set_default

    inspect_string = group.inspect

    assert_includes inspect_string, "BetterService::Workflows::BranchGroup"
    assert_includes inspect_string, "name=:my_group"
    assert_includes inspect_string, "branches=2"
    assert_includes inspect_string, "has_default=true"
  end
end
