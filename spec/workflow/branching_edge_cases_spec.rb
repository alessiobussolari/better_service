# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workflow Branching Edge Cases", type: :workflow do
  class EdgeCaseTestUser
    attr_accessor :id, :name

    def initialize(id, name = "Test User")
      @id = id
      @name = name
    end
  end

  # Mock services
  class EdgeCaseSimpleService < BetterService::Services::Base
    schema { optional(:context).filled }
    process_with { { resource: { executed: true } } }
  end

  class EdgeCaseContextModifyingService < BetterService::Services::Base
    schema { optional(:context).filled }
    process_with do
      { resource: { new_value: rand(100) } }
    end
  end

  class EdgeCaseFailingService < BetterService::Services::Base
    schema { optional(:context).filled }
    process_with { raise StandardError, "Service failed" }
  end

  let(:user) { EdgeCaseTestUser.new(1) }

  describe "Branch Conditions That Raise Exceptions" do
    it "treats branch condition that raises exception as false" do
      workflow_class = Class.new(BetterService::Workflows::Base) do
        step :init, with: EdgeCaseSimpleService

        branch do
          on ->(ctx) { raise StandardError, "Condition error" } do
            step :should_not_execute, with: EdgeCaseSimpleService
          end

          otherwise do
            step :should_execute, with: EdgeCaseSimpleService
          end
        end
      end

      result = workflow_class.new(user, params: {}).call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to eq([ :init, :should_execute ])
      expect(result[:metadata][:branches_taken]).to include("branch_1:otherwise")
    end
  end

  describe "Branch with Empty Steps" do
    it "executes successfully with no steps" do
      workflow_class = Class.new(BetterService::Workflows::Base) do
        step :init, with: EdgeCaseSimpleService

        branch do
          on ->(ctx) { true } do
            # No steps in this branch
          end

          otherwise do
            step :otherwise_step, with: EdgeCaseSimpleService
          end
        end

        step :final, with: EdgeCaseSimpleService
      end

      result = workflow_class.new(user, params: {}).call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to eq([ :init, :final ])
      expect(result[:metadata][:branches_taken]).to include("branch_1:on_1")
    end
  end

  describe "Deeply Nested Branches" do
    it "executes correctly with 5 levels of nesting" do
      workflow_class = Class.new(BetterService::Workflows::Base) do
        step :init, with: EdgeCaseSimpleService

        branch do
          on ->(ctx) { true } do
            branch do
              on ->(ctx) { true } do
                branch do
                  on ->(ctx) { true } do
                    branch do
                      on ->(ctx) { true } do
                        branch do
                          on ->(ctx) { true } do
                            step :deeply_nested, with: EdgeCaseSimpleService
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end

        step :final, with: EdgeCaseSimpleService
      end

      result = workflow_class.new(user, params: {}).call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to eq([ :init, :deeply_nested, :final ])
      expect(result[:metadata][:branches_taken].count).to eq(5)
    end
  end

  describe "Branch with Optional Steps That Fail" do
    it "does not stop workflow when optional step fails" do
      workflow_class = Class.new(BetterService::Workflows::Base) do
        step :init, with: EdgeCaseSimpleService

        branch do
          on ->(ctx) { true } do
            step :failing_optional,
                 with: EdgeCaseFailingService,
                 optional: true

            step :after_optional, with: EdgeCaseSimpleService
          end
        end

        step :final, with: EdgeCaseSimpleService
      end

      result = workflow_class.new(user, params: {}).call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to eq([ :init, :after_optional, :final ])
    end
  end

  describe "Context Modified During Branch Execution" do
    it "can use context modified by previous steps in same branch" do
      workflow_class = Class.new(BetterService::Workflows::Base) do
        step :init, with: EdgeCaseSimpleService

        branch do
          on ->(ctx) { true } do
            step :modify_context, with: EdgeCaseContextModifyingService

            branch do
              on ->(ctx) { ctx.modify_context[:new_value] > 50 } do
                step :high_value, with: EdgeCaseSimpleService
              end

              otherwise do
                step :low_value, with: EdgeCaseSimpleService
              end
            end
          end
        end
      end

      result = workflow_class.new(user, params: {}).call

      expect(result[:success]).to be true
      expect(
        result[:metadata][:steps_executed].include?(:high_value) ||
        result[:metadata][:steps_executed].include?(:low_value)
      ).to be true
    end
  end

  describe "Multiple Branches in Sequence" do
    it "handles multiple sequential branch blocks correctly" do
      workflow_class = Class.new(BetterService::Workflows::Base) do
        step :init, with: EdgeCaseSimpleService

        branch do
          on ->(ctx) { ctx.init[:executed] } do
            step :first_branch_path, with: EdgeCaseSimpleService
          end
        end

        branch do
          on ->(ctx) { ctx.first_branch_path[:executed] } do
            step :second_branch_path, with: EdgeCaseSimpleService
          end
        end

        branch do
          on ->(ctx) { ctx.second_branch_path[:executed] } do
            step :third_branch_path, with: EdgeCaseSimpleService
          end
        end

        step :final, with: EdgeCaseSimpleService
      end

      result = workflow_class.new(user, params: {}).call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to eq(
        [ :init, :first_branch_path, :second_branch_path, :third_branch_path, :final ]
      )
      expect(result[:metadata][:branches_taken].count).to eq(3)
    end
  end

  describe "Branch with Conditional Step Inside" do
    it "can contain conditional steps with if clause" do
      workflow_class = Class.new(BetterService::Workflows::Base) do
        step :init, with: EdgeCaseSimpleService

        branch do
          on ->(ctx) { true } do
            step :always_execute, with: EdgeCaseSimpleService

            step :conditionally_execute,
                 with: EdgeCaseSimpleService,
                 if: ->(ctx) { false }

            step :also_always_execute, with: EdgeCaseSimpleService
          end
        end
      end

      result = workflow_class.new(user, params: {}).call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to eq([ :init, :always_execute, :also_always_execute ])
    end
  end

  describe "No Matching Branch Without Otherwise" do
    it "raises configuration error when no branch matches" do
      workflow_class = Class.new(BetterService::Workflows::Base) do
        step :init, with: EdgeCaseSimpleService

        branch do
          on ->(ctx) { false } do
            step :should_not_execute, with: EdgeCaseSimpleService
          end

          on ->(ctx) { false } do
            step :also_should_not_execute, with: EdgeCaseSimpleService
          end
        end
      end

      expect {
        workflow_class.new(user, params: {}).call
      }.to raise_error(BetterService::Errors::Configuration::InvalidConfigurationError) do |error|
        expect(error.message).to match(/No matching branch found/)
        expect(error.code).to eq(:configuration_error)
      end
    end
  end

  describe "Branch Rollback with Custom Rollback Logic" do
    it "properly raises error when step fails in branch" do
      service1 = Class.new(BetterService::Services::Base) do
        schema { optional(:context).filled }
        process_with { { resource: { id: 1 } } }
      end

      service2 = Class.new(BetterService::Services::Base) do
        schema { optional(:context).filled }
        process_with { { resource: { id: 2 } } }
      end

      workflow_class = Class.new(BetterService::Workflows::Base) do
        with_transaction true

        step :init, with: EdgeCaseSimpleService

        branch do
          on ->(ctx) { true } do
            step :step1, with: service1
            step :step2, with: service2
            step :failing_step, with: EdgeCaseFailingService
          end
        end
      end

      expect {
        workflow_class.new(user, params: {}).call
      }.to raise_error(BetterService::Errors::Workflowable::Runtime::StepExecutionError) do |error|
        expect(error.message).to match(/failing_step failed/)
      end
    end
  end

  describe "Branch Condition Accessing Non-existent Context Key" do
    it "handles gracefully" do
      workflow_class = Class.new(BetterService::Workflows::Base) do
        step :init, with: EdgeCaseSimpleService

        branch do
          on ->(ctx) {
            ctx.respond_to?(:nonexistent_key) && ctx.nonexistent_key&.value == "something"
          } do
            step :should_not_execute, with: EdgeCaseSimpleService
          end

          otherwise do
            step :should_execute, with: EdgeCaseSimpleService
          end
        end
      end

      result = workflow_class.new(user, params: {}).call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to eq([ :init, :should_execute ])
    end
  end

  describe "Time-dependent Branch Conditions" do
    it "can use time-dependent conditions" do
      workflow_class = Class.new(BetterService::Workflows::Base) do
        step :init, with: EdgeCaseSimpleService

        branch do
          on ->(ctx) { Time.current.hour >= 0 && Time.current.hour < 12 } do
            step :morning_action, with: EdgeCaseSimpleService
          end

          on ->(ctx) { Time.current.hour >= 12 && Time.current.hour < 18 } do
            step :afternoon_action, with: EdgeCaseSimpleService
          end

          otherwise do
            step :evening_action, with: EdgeCaseSimpleService
          end
        end
      end

      result = workflow_class.new(user, params: {}).call

      expect(result[:success]).to be true
      expect(
        result[:metadata][:steps_executed].include?(:morning_action) ||
        result[:metadata][:steps_executed].include?(:afternoon_action) ||
        result[:metadata][:steps_executed].include?(:evening_action)
      ).to be true
    end
  end

  describe "Branch with Complex Boolean Logic" do
    it "handles complex AND/OR conditions" do
      workflow_class = Class.new(BetterService::Workflows::Base) do
        step :init, with: EdgeCaseSimpleService

        branch do
          on ->(ctx) {
            (ctx.user.id > 0 && ctx.user.name.present?) ||
            (ctx.init[:executed] && !ctx.init[:executed].nil?)
          } do
            step :complex_condition_met, with: EdgeCaseSimpleService
          end

          otherwise do
            step :complex_condition_not_met, with: EdgeCaseSimpleService
          end
        end
      end

      result = workflow_class.new(user, params: {}).call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to eq([ :init, :complex_condition_met ])
    end
  end

  describe "Branch with Params Access" do
    it "allows conditions to access workflow params" do
      workflow_class = Class.new(BetterService::Workflows::Base) do
        step :init, with: EdgeCaseSimpleService

        branch do
          on ->(ctx) { ctx.mode == "fast" } do
            step :fast_processing, with: EdgeCaseSimpleService
          end

          on ->(ctx) { ctx.mode == "slow" } do
            step :slow_processing, with: EdgeCaseSimpleService
          end

          otherwise do
            step :default_processing, with: EdgeCaseSimpleService
          end
        end
      end

      # Test with fast mode
      fast_result = workflow_class.new(user, params: { mode: "fast" }).call
      expect(fast_result[:success]).to be true
      expect(fast_result[:metadata][:steps_executed]).to include(:fast_processing)

      # Test with slow mode
      slow_result = workflow_class.new(user, params: { mode: "slow" }).call
      expect(slow_result[:success]).to be true
      expect(slow_result[:metadata][:steps_executed]).to include(:slow_processing)

      # Test with no mode (default)
      default_result = workflow_class.new(user, params: {}).call
      expect(default_result[:success]).to be true
      expect(default_result[:metadata][:steps_executed]).to include(:default_processing)
    end
  end

  describe "Branch After Failed Optional Step" do
    it "executes correctly after failed optional step" do
      workflow_class = Class.new(BetterService::Workflows::Base) do
        step :init, with: EdgeCaseSimpleService

        step :optional_failing,
             with: EdgeCaseFailingService,
             optional: true

        branch do
          on ->(ctx) { ctx.init[:executed] } do
            step :branch_step, with: EdgeCaseSimpleService
          end
        end

        step :final, with: EdgeCaseSimpleService
      end

      result = workflow_class.new(user, params: {}).call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to include(:init)
      expect(result[:metadata][:steps_executed]).to include(:optional_failing)
      expect(result[:metadata][:steps_executed]).to include(:branch_step)
      expect(result[:metadata][:steps_executed]).to include(:final)
      expect(result[:context]).to respond_to(:optional_failing_error)
    end
  end

  describe "Empty Branch Block" do
    it "raises validation error" do
      expect {
        Class.new(BetterService::Workflows::Base) do
          step :init, with: EdgeCaseSimpleService

          branch do
            # Empty - no on/otherwise blocks
          end
        end
      }.to raise_error(BetterService::Errors::Configuration::InvalidConfigurationError, /must contain at least one/)
    end
  end
end
