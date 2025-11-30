# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterService::Workflows::BranchGroup do
  class BranchGroupTestUser
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
  class BranchGroupTestMockService < BetterService::Services::Base
    schema do
      optional(:path).maybe(:string)
    end

    process_with do |_data|
      { resource: { path: params[:path] || "default" } }
    end
  end

  let(:user) { BranchGroupTestUser.new(1) }
  let(:context) { BetterService::Workflowable::Context.new(user) }

  describe "#initialize" do
    it "initializes with empty branches and no default" do
      group = described_class.new(name: :test_group)

      expect(group.name).to eq(:test_group)
      expect(group.branches).to be_empty
      expect(group.default_branch).to be_nil
    end

    it "initializes without name" do
      group = described_class.new

      expect(group.name).to be_nil
    end
  end

  describe "#add_branch" do
    it "creates and returns a new branch" do
      group = described_class.new(name: :test_group)

      condition = ->(ctx) { ctx.user.premium? }
      branch = group.add_branch(condition: condition, name: :premium_path)

      expect(branch).to be_instance_of(BetterService::Workflows::Branch)
      expect(branch.condition).to eq(condition)
      expect(branch.name).to eq(:premium_path)
    end

    it "adds branch to branches array" do
      group = described_class.new

      group.add_branch(condition: ->(ctx) { true }, name: :first)
      group.add_branch(condition: ->(ctx) { false }, name: :second)

      expect(group.branches.count).to eq(2)
      expect(group.branches.map(&:name)).to eq([:first, :second])
    end
  end

  describe "#set_default" do
    it "creates default branch" do
      group = described_class.new

      default = group.set_default(name: :fallback)

      expect(default).to be_instance_of(BetterService::Workflows::Branch)
      expect(default.condition).to be_nil
      expect(default.name).to eq(:fallback)
      expect(group.default_branch).to eq(default)
    end

    it "uses :otherwise as default name" do
      group = described_class.new

      default = group.set_default

      expect(default.name).to eq(:otherwise)
    end
  end

  describe "#select_branch" do
    it "returns first matching branch" do
      group = described_class.new
      context.value = 100

      branch1 = group.add_branch(condition: ->(ctx) { ctx.value > 200 }, name: :high)
      branch2 = group.add_branch(condition: ->(ctx) { ctx.value > 50 }, name: :medium)
      branch3 = group.add_branch(condition: ->(ctx) { ctx.value > 10 }, name: :low)

      selected = group.select_branch(context)

      expect(selected).to eq(branch2)
      expect(selected.name).to eq(:medium)
    end

    it "returns default when no condition matches" do
      group = described_class.new
      context.value = 5

      group.add_branch(condition: ->(ctx) { ctx.value > 100 }, name: :high)
      default = group.set_default(name: :fallback)

      selected = group.select_branch(context)

      expect(selected).to eq(default)
    end

    it "returns nil when no match and no default" do
      group = described_class.new
      context.value = 5

      group.add_branch(condition: ->(ctx) { ctx.value > 100 }, name: :high)

      selected = group.select_branch(context)

      expect(selected).to be_nil
    end

    it "evaluates conditions in order" do
      group = described_class.new
      context.type = "A"

      first = group.add_branch(condition: ->(ctx) { ctx.type == "A" }, name: :first)
      group.add_branch(condition: ->(ctx) { ctx.type == "A" }, name: :second)

      selected = group.select_branch(context)

      expect(selected).to eq(first)
    end
  end

  describe "#call" do
    it "executes matching branch steps" do
      group = described_class.new(name: :payment_routing)
      context.payment_type = "card"

      card_branch = group.add_branch(
        condition: ->(ctx) { ctx.payment_type == "card" },
        name: :card_path
      )
      card_branch.add_step(
        BetterService::Workflowable::Step.new(
          name: :process_card,
          service_class: BranchGroupTestMockService,
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
          service_class: BranchGroupTestMockService,
          input: ->(ctx) { { path: "paypal" } }
        )
      )

      result = group.call(context, user, {})

      expect(result[:executed_steps].map(&:name)).to eq([:process_card])
      expect(result[:branch_taken]).to eq(card_branch)
      expect(result[:branch_decisions]).to include("payment_routing:card_path")
    end

    it "raises InvalidConfigurationError when no branch matches" do
      group = described_class.new(name: :test_group)
      context.value = 0

      group.add_branch(condition: ->(ctx) { ctx.value > 100 }, name: :high)

      expect {
        group.call(context, user, {})
      }.to raise_error(BetterService::Errors::Configuration::InvalidConfigurationError) do |error|
        expect(error.code).to eq(:configuration_error)
        expect(error.message).to include("No matching branch")
        expect(error.context[:branch_group]).to eq(:test_group)
        expect(error.context[:branches_count]).to eq(1)
        expect(error.context[:has_default]).to eq(false)
      end
    end

    it "returns branch decisions for tracking" do
      group = described_class.new(name: :routing)
      context.tier = "gold"

      group.add_branch(condition: ->(ctx) { ctx.tier == "gold" }, name: :gold_path)

      result = group.call(context, user, {})

      expect(result[:branch_decisions]).to include("routing:gold_path")
      expect(result[:skipped]).to be_falsey
    end

    it "executes default branch when no condition matches" do
      group = described_class.new(name: :test)
      context.value = 0

      group.add_branch(condition: ->(ctx) { ctx.value > 100 }, name: :high)

      default = group.set_default
      default.add_step(
        BetterService::Workflowable::Step.new(
          name: :default_action,
          service_class: BranchGroupTestMockService
        )
      )

      result = group.call(context, user, {})

      expect(result[:executed_steps].map(&:name)).to eq([:default_action])
      expect(result[:branch_decisions]).to include("test:otherwise")
    end
  end

  describe "#branch_count" do
    it "returns count of conditional branches" do
      group = described_class.new

      group.add_branch(condition: ->(ctx) { true }, name: :a)
      group.add_branch(condition: ->(ctx) { true }, name: :b)

      expect(group.branch_count).to eq(2)
    end

    it "includes default branch in count" do
      group = described_class.new

      group.add_branch(condition: ->(ctx) { true }, name: :a)
      group.set_default

      expect(group.branch_count).to eq(2)
    end

    it "returns 0 for empty group" do
      group = described_class.new

      expect(group.branch_count).to eq(0)
    end
  end

  describe "#has_default?" do
    it "returns false when no default set" do
      group = described_class.new

      expect(group.has_default?).to be false
    end

    it "returns true when default is set" do
      group = described_class.new
      group.set_default

      expect(group.has_default?).to be true
    end
  end

  describe "#inspect" do
    it "returns informative string" do
      group = described_class.new(name: :my_group)

      group.add_branch(condition: ->(ctx) { true }, name: :a)
      group.add_branch(condition: ->(ctx) { false }, name: :b)
      group.set_default

      inspect_string = group.inspect

      expect(inspect_string).to include("BetterService::Workflows::BranchGroup")
      expect(inspect_string).to include("name=:my_group")
      expect(inspect_string).to include("branches=2")
      expect(inspect_string).to include("has_default=true")
    end
  end
end
