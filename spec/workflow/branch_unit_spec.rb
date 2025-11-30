# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterService::Workflows::Branch do
  class BranchUnitTestUser
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
  class BranchUnitTestMockStepService < BetterService::Services::Base
    schema do
      optional(:value).maybe(:integer)
    end

    process_with do |_data|
      { resource: { processed: true, value: params[:value] } }
    end
  end

  class BranchUnitTestFailingStepService < BetterService::Services::Base
    schema do
      optional(:fail).maybe(:bool)
    end

    process_with do |_data|
      raise StandardError, "Step service failed"
    end
  end

  let(:user) { BranchUnitTestUser.new(1) }
  let(:context) { BetterService::Workflowable::Context.new(user) }

  describe "#initialize" do
    it "initializes with condition and name" do
      condition = ->(ctx) { ctx.user.premium? }
      branch = described_class.new(condition: condition, name: :premium_path)

      expect(branch.condition).to eq(condition)
      expect(branch.name).to eq(:premium_path)
      expect(branch.steps).to be_empty
    end

    it "initializes with nil condition for default branch" do
      branch = described_class.new(condition: nil, name: :default)

      expect(branch.condition).to be_nil
      expect(branch.default?).to be true
    end

    it "starts with empty steps array" do
      branch = described_class.new

      expect(branch.steps).to be_instance_of(Array)
      expect(branch.steps).to be_empty
    end
  end

  describe "#matches?" do
    it "returns true when condition evaluates to true" do
      context.should_match = true

      branch = described_class.new(condition: ->(ctx) { ctx.should_match })

      expect(branch.matches?(context)).to be true
    end

    it "returns false when condition evaluates to false" do
      context.should_match = false

      branch = described_class.new(condition: ->(ctx) { ctx.should_match })

      expect(branch.matches?(context)).to be false
    end

    it "always returns true for default branch (nil condition)" do
      branch = described_class.new(condition: nil)

      expect(branch.matches?(context)).to be true
    end

    it "handles complex conditions" do
      context.amount = 150
      context.status = "active"

      branch = described_class.new(
        condition: ->(ctx) { ctx.amount > 100 && ctx.status == "active" }
      )

      expect(branch.matches?(context)).to be true
    end

    it "returns false when condition raises error" do
      branch = described_class.new(
        condition: ->(ctx) { raise "Condition error" }
      )

      expect(branch.matches?(context)).to be false
    end

    it "works with user object in context" do
      premium_user = BranchUnitTestUser.new(1, premium: true)
      premium_context = BetterService::Workflowable::Context.new(premium_user)

      branch = described_class.new(
        condition: ->(ctx) { ctx.user.premium? }
      )

      expect(branch.matches?(premium_context)).to be true
    end
  end

  describe "#add_step" do
    it "adds a step to the branch" do
      branch = described_class.new(name: :test_branch)

      step = BetterService::Workflowable::Step.new(
        name: :test_step,
        service_class: BranchUnitTestMockStepService
      )

      branch.add_step(step)

      expect(branch.steps.count).to eq(1)
      expect(branch.steps.first).to eq(step)
    end

    it "maintains order of steps" do
      branch = described_class.new(name: :test_branch)

      step1 = BetterService::Workflowable::Step.new(name: :step1, service_class: BranchUnitTestMockStepService)
      step2 = BetterService::Workflowable::Step.new(name: :step2, service_class: BranchUnitTestMockStepService)
      step3 = BetterService::Workflowable::Step.new(name: :step3, service_class: BranchUnitTestMockStepService)

      branch.add_step(step1)
      branch.add_step(step2)
      branch.add_step(step3)

      expect(branch.steps.map(&:name)).to eq([:step1, :step2, :step3])
    end

    it "returns updated steps array" do
      branch = described_class.new

      step = BetterService::Workflowable::Step.new(name: :test, service_class: BranchUnitTestMockStepService)
      result = branch.add_step(step)

      expect(result).to be_instance_of(Array)
      expect(result).to include(step)
    end
  end

  describe "#execute" do
    it "runs all steps in branch" do
      branch = described_class.new(name: :test_branch)

      step1 = BetterService::Workflowable::Step.new(name: :step1, service_class: BranchUnitTestMockStepService)
      step2 = BetterService::Workflowable::Step.new(name: :step2, service_class: BranchUnitTestMockStepService)

      branch.add_step(step1)
      branch.add_step(step2)

      executed_steps = branch.execute(context, user, {})

      expect(executed_steps.count).to eq(2)
      expect(executed_steps.map(&:name)).to eq([:step1, :step2])
    end

    it "stores step results in context" do
      branch = described_class.new(name: :test_branch)

      step = BetterService::Workflowable::Step.new(
        name: :process_step,
        service_class: BranchUnitTestMockStepService,
        input: ->(ctx) { { value: 42 } }
      )

      branch.add_step(step)
      branch.execute(context, user, {})

      expect(context.process_step).to eq({ processed: true, value: 42 })
    end

    it "returns empty array when no steps defined" do
      branch = described_class.new(name: :empty_branch)

      executed_steps = branch.execute(context, user, {})

      expect(executed_steps).to be_empty
    end

    it "skips steps with false conditions" do
      branch = described_class.new(name: :test_branch)
      context.should_run = false

      step = BetterService::Workflowable::Step.new(
        name: :conditional_step,
        service_class: BranchUnitTestMockStepService,
        condition: ->(ctx) { ctx.should_run }
      )

      branch.add_step(step)
      executed_steps = branch.execute(context, user, {})

      expect(executed_steps).to be_empty
    end

    it "raises error when required step fails" do
      branch = described_class.new(name: :test_branch)

      step = BetterService::Workflowable::Step.new(
        name: :failing_step,
        service_class: BranchUnitTestFailingStepService,
        optional: false
      )

      branch.add_step(step)

      expect {
        branch.execute(context, user, {})
      }.to raise_error(BetterService::Errors::Workflowable::Runtime::StepExecutionError) do |error|
        expect(error.code).to eq(:step_failed)
        expect(error.message).to include("failing_step failed")
      end
    end

    it "continues when optional step fails" do
      branch = described_class.new(name: :test_branch)

      optional_step = BetterService::Workflowable::Step.new(
        name: :optional_step,
        service_class: BranchUnitTestFailingStepService,
        optional: true
      )

      next_step = BetterService::Workflowable::Step.new(
        name: :next_step,
        service_class: BranchUnitTestMockStepService
      )

      branch.add_step(optional_step)
      branch.add_step(next_step)

      executed_steps = branch.execute(context, user, {})

      expect(executed_steps.map(&:name)).to eq([:next_step])
    end
  end

  describe "#default?" do
    it "returns true when condition is nil" do
      branch = described_class.new(condition: nil)

      expect(branch.default?).to be true
    end

    it "returns false when condition is present" do
      branch = described_class.new(condition: ->(ctx) { true })

      expect(branch.default?).to be false
    end
  end

  describe "#inspect" do
    it "returns informative string" do
      branch = described_class.new(
        condition: ->(ctx) { true },
        name: :my_branch
      )

      step = BetterService::Workflowable::Step.new(name: :step1, service_class: BranchUnitTestMockStepService)
      branch.add_step(step)

      inspect_string = branch.inspect

      expect(inspect_string).to include("BetterService::Workflows::Branch")
      expect(inspect_string).to include("name=:my_branch")
      expect(inspect_string).to include("condition=present")
      expect(inspect_string).to include("steps=1")
    end

    it "shows nil condition for default branch" do
      branch = described_class.new(condition: nil, name: :default)

      inspect_string = branch.inspect

      expect(inspect_string).to include("condition=nil")
    end
  end
end
