# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetterService::Workflows::BranchDSL do
  # Mock service for testing
  class BranchDSLTestMockService < BetterService::Services::Base
    schema do
      optional(:value).maybe(:integer)
    end

    process_with do |_data|
      { resource: { value: params[:value] || 42 } }
    end
  end

  let(:branch_group) { BetterService::Workflows::BranchGroup.new(name: :test_group) }
  let(:dsl) { described_class.new(branch_group) }

  describe "#initialize" do
    it "initializes with branch group" do
      expect(dsl.branch_group).to eq(branch_group)
    end
  end

  describe "#on" do
    it "creates a conditional branch" do
      dsl.on ->(ctx) { ctx.premium? } do
        step :premium_step, with: BranchDSLTestMockService
      end

      expect(branch_group.branches.count).to eq(1)
      expect(branch_group.branches.first.name).to eq(:on_1)
    end

    it "requires a Proc condition" do
      expect {
        dsl.on "not a proc" do
          step :test, with: BranchDSLTestMockService
        end
      }.to raise_error(ArgumentError, /Condition must be a Proc/)
    end

    it "requires a block" do
      expect {
        dsl.on ->(ctx) { true }
      }.to raise_error(ArgumentError, /Block required/)
    end

    it "increments branch index for naming" do
      dsl.on(->(ctx) { true }) { step :step1, with: BranchDSLTestMockService }
      dsl.on(->(ctx) { false }) { step :step2, with: BranchDSLTestMockService }
      dsl.on(->(ctx) { true }) { step :step3, with: BranchDSLTestMockService }

      expect(branch_group.branches.map(&:name)).to eq([:on_1, :on_2, :on_3])
    end

    it "adds steps to the correct branch" do
      dsl.on ->(ctx) { ctx.type == "A" } do
        step :step_a1, with: BranchDSLTestMockService
        step :step_a2, with: BranchDSLTestMockService
      end

      dsl.on ->(ctx) { ctx.type == "B" } do
        step :step_b1, with: BranchDSLTestMockService
      end

      branch_a = branch_group.branches[0]
      branch_b = branch_group.branches[1]

      expect(branch_a.steps.map(&:name)).to eq([:step_a1, :step_a2])
      expect(branch_b.steps.map(&:name)).to eq([:step_b1])
    end
  end

  describe "#otherwise" do
    it "creates default branch" do
      dsl.otherwise do
        step :default_step, with: BranchDSLTestMockService
      end

      expect(branch_group.has_default?).to be true
      expect(branch_group.default_branch.name).to eq(:otherwise)
    end

    it "requires a block" do
      expect {
        dsl.otherwise
      }.to raise_error(ArgumentError, /Block required/)
    end

    it "can only be called once" do
      dsl.otherwise { step :default1, with: BranchDSLTestMockService }

      expect {
        dsl.otherwise { step :default2, with: BranchDSLTestMockService }
      }.to raise_error(ArgumentError, /Default branch already defined/)
    end

    it "adds steps to default branch" do
      dsl.otherwise do
        step :default_step1, with: BranchDSLTestMockService
        step :default_step2, with: BranchDSLTestMockService
      end

      default = branch_group.default_branch
      expect(default.steps.map(&:name)).to eq([:default_step1, :default_step2])
    end
  end

  describe "#step" do
    it "raises error when called outside branch" do
      expect {
        dsl.step :orphan_step, with: BranchDSLTestMockService
      }.to raise_error(RuntimeError, /must be called within/)
    end

    it "creates Step object with correct attributes" do
      dsl.on ->(ctx) { true } do
        step :test_step,
             with: BranchDSLTestMockService,
             input: ->(ctx) { { value: 100 } },
             optional: true
      end

      step = branch_group.branches.first.steps.first

      expect(step.name).to eq(:test_step)
      expect(step.service_class).to eq(BranchDSLTestMockService)
      expect(step.optional).to be true
    end

    it "supports rollback option" do
      rollback_proc = ->(ctx) { ctx.rollback_called = true }

      dsl.on ->(ctx) { true } do
        step :with_rollback,
             with: BranchDSLTestMockService,
             rollback: rollback_proc
      end

      step = branch_group.branches.first.steps.first

      expect(step.rollback_block).not_to be_nil
    end
  end

  describe "#branch (nested)" do
    it "creates nested branch group" do
      dsl.on ->(ctx) { ctx.type == "contract" } do
        step :validate, with: BranchDSLTestMockService

        branch do
          on ->(ctx) { ctx.value > 10000 } do
            step :ceo_approval, with: BranchDSLTestMockService
          end

          otherwise do
            step :manager_approval, with: BranchDSLTestMockService
          end
        end
      end

      outer_branch = branch_group.branches.first
      expect(outer_branch.steps.count).to eq(2)

      # First should be a step
      expect(outer_branch.steps[0]).to be_instance_of(BetterService::Workflowable::Step)
      expect(outer_branch.steps[0].name).to eq(:validate)

      # Second should be a nested BranchGroup
      nested_group = outer_branch.steps[1]
      expect(nested_group).to be_instance_of(BetterService::Workflows::BranchGroup)
      expect(nested_group.branches.count).to eq(1)
      expect(nested_group.has_default?).to be true
    end

    it "raises error when called outside branch" do
      expect {
        dsl.branch do
          on ->(ctx) { true } do
            step :test, with: BranchDSLTestMockService
          end
        end
      }.to raise_error(RuntimeError, /must be called within/)
    end

    it "supports valid on block with steps" do
      dsl.on ->(ctx) { true } do
        step :valid_step, with: BranchDSLTestMockService
      end

      expect(branch_group.branches.count).to eq(1)
    end
  end

  describe "complex DSL composition" do
    it "supports complex multi-branch composition" do
      dsl.on ->(ctx) { ctx.priority == "high" } do
        step :urgent_process, with: BranchDSLTestMockService
        step :notify_manager, with: BranchDSLTestMockService
      end

      dsl.on ->(ctx) { ctx.priority == "medium" } do
        step :standard_process, with: BranchDSLTestMockService
      end

      dsl.on ->(ctx) { ctx.priority == "low" } do
        step :batch_process, with: BranchDSLTestMockService
      end

      dsl.otherwise do
        step :queue_for_review, with: BranchDSLTestMockService
      end

      expect(branch_group.branches.count).to eq(3)
      expect(branch_group.has_default?).to be true
      expect(branch_group.branch_count).to eq(4)
    end

    it "isolates branch steps between on blocks" do
      dsl.on(->(ctx) { true }) { step :branch1_step, with: BranchDSLTestMockService }
      dsl.on(->(ctx) { true }) { step :branch2_step, with: BranchDSLTestMockService }
      dsl.otherwise { step :default_step, with: BranchDSLTestMockService }

      expect(branch_group.branches[0].steps.count).to eq(1)
      expect(branch_group.branches[1].steps.count).to eq(1)
      expect(branch_group.default_branch.steps.count).to eq(1)

      expect(branch_group.branches[0].steps.first.name).to eq(:branch1_step)
      expect(branch_group.branches[1].steps.first.name).to eq(:branch2_step)
      expect(branch_group.default_branch.steps.first.name).to eq(:default_step)
    end
  end
end
