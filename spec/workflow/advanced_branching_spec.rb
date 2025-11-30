# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Advanced Workflow Branching" do
  # Test user class
  class AdvancedBranchingTestUser
    attr_accessor :id, :tier, :region

    def initialize(id, tier: "free", region: "US")
      @id = id
      @tier = tier
      @region = region
    end

    def premium?
      tier == "premium"
    end

    def enterprise?
      tier == "enterprise"
    end
  end

  # Mock services for testing
  class AdvancedBranchingMockService < BetterService::Services::Base
    schema do
      optional(:value).maybe(:integer)
      optional(:label).maybe(:string)
    end

    process_with do |_data|
      { resource: { processed: true, value: params[:value], label: params[:label] } }
    end
  end

  class AdvancedBranchingFailingService < BetterService::Services::Base
    schema do
      optional(:should_fail).maybe(:bool)
    end

    process_with do |_data|
      raise StandardError, "Intentional failure for testing"
    end
  end

  class AdvancedBranchingSlowService < BetterService::Services::Base
    schema do
      optional(:delay_ms).maybe(:integer)
    end

    process_with do |_data|
      sleep((params[:delay_ms] || 10) / 1000.0)
      { resource: { completed: true } }
    end
  end

  let(:user) { AdvancedBranchingTestUser.new(1, tier: "free") }

  describe "Triple-nested branches" do
    class TripleNestedBranchWorkflow < BetterService::Workflows::Base
      step :initial, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "initial" } }

      branch do
        on ->(ctx) { ctx.user.tier == "enterprise" } do
          step :enterprise_check, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "enterprise" } }

          branch do
            on ->(ctx) { ctx.user.region == "EU" } do
              step :eu_compliance, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "eu_compliance" } }

              branch do
                on ->(ctx) { ctx.initial[:value].to_i > 1000 } do
                  step :high_value_eu, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "high_value_eu" } }
                end

                otherwise do
                  step :standard_eu, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "standard_eu" } }
                end
              end
            end

            otherwise do
              step :global_enterprise, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "global_enterprise" } }
            end
          end
        end

        on ->(ctx) { ctx.user.premium? } do
          step :premium_path, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "premium" } }
        end

        otherwise do
          step :free_path, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "free" } }
        end
      end

      step :finalize, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "finalize" } }
    end

    it "executes through all three nested branch levels" do
      enterprise_eu_user = AdvancedBranchingTestUser.new(1, tier: "enterprise", region: "EU")
      workflow = TripleNestedBranchWorkflow.new(enterprise_eu_user, params: {})

      result = workflow.call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to include(:initial, :enterprise_check, :eu_compliance, :standard_eu, :finalize)
    end

    it "tracks all branch decisions in metadata" do
      enterprise_eu_user = AdvancedBranchingTestUser.new(1, tier: "enterprise", region: "EU")
      workflow = TripleNestedBranchWorkflow.new(enterprise_eu_user, params: {})

      result = workflow.call

      expect(result[:metadata][:branches_taken].length).to be >= 3
    end

    it "takes free path for free tier user" do
      free_user = AdvancedBranchingTestUser.new(1, tier: "free")
      workflow = TripleNestedBranchWorkflow.new(free_user, params: {})

      result = workflow.call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to include(:free_path)
      expect(result[:metadata][:steps_executed]).not_to include(:enterprise_check)
    end
  end

  describe "Branch with multiple rollback points" do
    let(:rollback_tracker) { [] }

    it "tracks multiple rollback executions in LIFO order" do
      tracker = []

      workflow_class = Class.new(BetterService::Workflows::Base) do
        step :step1, with: AdvancedBranchingMockService,
             input: ->(ctx) { { label: "step1" } },
             rollback: ->(ctx) { tracker << :rollback1 }

        step :step2, with: AdvancedBranchingMockService,
             input: ->(ctx) { { label: "step2" } },
             rollback: ->(ctx) { tracker << :rollback2 }

        step :failing_step, with: AdvancedBranchingFailingService,
             rollback: ->(ctx) { tracker << :rollback3 }
      end

      workflow = workflow_class.new(user, params: {})

      expect {
        workflow.call
      }.to raise_error(BetterService::Errors::Workflowable::Runtime::StepExecutionError)

      # Rollbacks should execute in reverse order (LIFO)
      expect(tracker).to eq([:rollback2, :rollback1])
    end
  end

  describe "Branch condition with context mutations" do
    class ContextMutatingWorkflow < BetterService::Workflows::Base
      step :set_flag, with: AdvancedBranchingMockService, input: ->(ctx) { { value: 100 } }

      branch do
        on ->(ctx) { ctx.set_flag[:value] > 50 } do
          step :high_value, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "high" } }
        end

        otherwise do
          step :low_value, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "low" } }
        end
      end
    end

    it "evaluates condition based on previous step results" do
      workflow = ContextMutatingWorkflow.new(user, params: {})
      result = workflow.call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to include(:high_value)
    end
  end

  describe "Mixed linear + branched steps" do
    class MixedLinearBranchWorkflow < BetterService::Workflows::Base
      step :linear1, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "linear1" } }
      step :linear2, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "linear2" } }

      branch do
        on ->(ctx) { ctx.user.premium? } do
          step :premium_feature, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "premium" } }
        end

        otherwise do
          step :basic_feature, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "basic" } }
        end
      end

      step :linear3, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "linear3" } }
      step :linear4, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "linear4" } }
    end

    it "executes linear steps before and after branch" do
      workflow = MixedLinearBranchWorkflow.new(user, params: {})
      result = workflow.call

      steps = result[:metadata][:steps_executed]
      expect(steps.index(:linear1)).to be < steps.index(:basic_feature)
      expect(steps.index(:basic_feature)).to be < steps.index(:linear3)
    end

    it "maintains correct step order with premium path" do
      premium_user = AdvancedBranchingTestUser.new(1, tier: "premium")
      workflow = MixedLinearBranchWorkflow.new(premium_user, params: {})
      result = workflow.call

      steps = result[:metadata][:steps_executed]
      expect(steps).to eq([:linear1, :linear2, :premium_feature, :linear3, :linear4])
    end
  end

  describe "Empty branch handling" do
    class EmptyBranchWorkflow < BetterService::Workflows::Base
      step :before, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "before" } }

      branch do
        on ->(ctx) { false } do
          # Empty branch - no steps
        end

        otherwise do
          step :default_step, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "default" } }
        end
      end

      step :after, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "after" } }
    end

    it "handles branches with no steps gracefully" do
      workflow = EmptyBranchWorkflow.new(user, params: {})
      result = workflow.call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to include(:before, :default_step, :after)
    end
  end

  describe "Branch with all conditions false (no otherwise)" do
    class NoOtherwiseBranchWorkflow < BetterService::Workflows::Base
      step :before, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "before" } }

      branch do
        on ->(ctx) { ctx.user.tier == "nonexistent" } do
          step :never_reached, with: AdvancedBranchingMockService
        end

        on ->(ctx) { ctx.user.tier == "also_nonexistent" } do
          step :also_never_reached, with: AdvancedBranchingMockService
        end
      end

      step :after, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "after" } }
    end

    it "raises configuration error when no branch matches and no otherwise" do
      workflow = NoOtherwiseBranchWorkflow.new(user, params: {})

      expect {
        workflow.call
      }.to raise_error(BetterService::Errors::Configuration::InvalidConfigurationError) do |error|
        expect(error.message).to include("No matching branch")
      end
    end
  end

  describe "First-match verification (parallel branch evaluation)" do
    class FirstMatchWorkflow < BetterService::Workflows::Base
      step :init, with: AdvancedBranchingMockService, input: ->(ctx) { { value: 50 } }

      branch do
        # Both conditions could be true, but first match wins
        on ->(ctx) { ctx.init[:value] > 25 } do
          step :first_match, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "first" } }
        end

        on ->(ctx) { ctx.init[:value] > 10 } do
          step :second_match, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "second" } }
        end

        otherwise do
          step :default, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "default" } }
        end
      end
    end

    it "executes only the first matching branch" do
      workflow = FirstMatchWorkflow.new(user, params: {})
      result = workflow.call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to include(:first_match)
      expect(result[:metadata][:steps_executed]).not_to include(:second_match)
      expect(result[:metadata][:steps_executed]).not_to include(:default)
    end
  end

  describe "Branch metadata accumulation" do
    class MetadataAccumulationWorkflow < BetterService::Workflows::Base
      step :step1, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "step1" } }

      branch do
        on ->(ctx) { true } do
          step :branch1_step, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "branch1" } }

          branch do
            on ->(ctx) { true } do
              step :nested_step, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "nested" } }
            end
          end
        end
      end

      step :final, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "final" } }
    end

    it "accumulates metadata from all executed steps" do
      workflow = MetadataAccumulationWorkflow.new(user, params: {})
      result = workflow.call

      expect(result[:metadata][:steps_executed].count).to eq(4)
      expect(result[:metadata]).to have_key(:branches_taken)
      expect(result[:metadata]).to have_key(:duration_ms)
    end

    it "records branch decisions at each level" do
      workflow = MetadataAccumulationWorkflow.new(user, params: {})
      result = workflow.call

      # Should have at least 2 branch decisions (outer + nested)
      expect(result[:metadata][:branches_taken].length).to be >= 2
    end
  end

  describe "Complex condition lambdas with external calls" do
    class ExternalConditionWorkflow < BetterService::Workflows::Base
      step :fetch_data, with: AdvancedBranchingMockService, input: ->(ctx) { { value: 42 } }

      branch do
        on ->(ctx) {
          # Complex condition with multiple checks
          data = ctx.fetch_data
          data[:value].present? &&
          data[:value].to_i > 0 &&
          ctx.user.respond_to?(:tier) &&
          ctx.user.tier != "banned"
        } do
          step :allowed_action, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "allowed" } }
        end

        otherwise do
          step :denied_action, with: AdvancedBranchingMockService, input: ->(ctx) { { label: "denied" } }
        end
      end
    end

    it "evaluates complex conditions correctly" do
      workflow = ExternalConditionWorkflow.new(user, params: {})
      result = workflow.call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to include(:allowed_action)
    end
  end

  describe "Branch step failure mid-execution" do
    class MidExecutionFailureWorkflow < BetterService::Workflows::Base
      step :step1, with: AdvancedBranchingMockService,
           input: ->(ctx) { { label: "step1" } },
           rollback: ->(ctx) { ctx.add(:rollback1_called, true) }

      branch do
        on ->(ctx) { true } do
          step :branch_step1, with: AdvancedBranchingMockService,
               input: ->(ctx) { { label: "branch1" } },
               rollback: ->(ctx) { ctx.add(:rollback_branch1_called, true) }

          step :failing_branch_step, with: AdvancedBranchingFailingService

          step :never_reached, with: AdvancedBranchingMockService,
               input: ->(ctx) { { label: "never" } }
        end
      end

      step :also_never_reached, with: AdvancedBranchingMockService,
           input: ->(ctx) { { label: "also_never" } }
    end

    it "stops execution at failing step within branch" do
      workflow = MidExecutionFailureWorkflow.new(user, params: {})

      expect {
        workflow.call
      }.to raise_error(BetterService::Errors::Workflowable::Runtime::StepExecutionError) do |error|
        expect(error.context[:step]).to eq(:failing_branch_step)
      end
    end
  end

  describe "Rollback order verification (LIFO)" do
    it "executes rollbacks in reverse order of step execution" do
      execution_order = []

      workflow_class = Class.new(BetterService::Workflows::Base) do
        step :a, with: AdvancedBranchingMockService,
             input: ->(ctx) { { label: "a" } },
             rollback: ->(ctx) { execution_order << :rollback_a }

        step :b, with: AdvancedBranchingMockService,
             input: ->(ctx) { { label: "b" } },
             rollback: ->(ctx) { execution_order << :rollback_b }

        step :c, with: AdvancedBranchingMockService,
             input: ->(ctx) { { label: "c" } },
             rollback: ->(ctx) { execution_order << :rollback_c }

        step :fail, with: AdvancedBranchingFailingService
      end

      workflow = workflow_class.new(user, params: {})

      expect { workflow.call }.to raise_error(BetterService::Errors::Workflowable::Runtime::StepExecutionError)

      # LIFO: c, b, a
      expect(execution_order).to eq([:rollback_c, :rollback_b, :rollback_a])
    end
  end
end
