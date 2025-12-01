# frozen_string_literal: true

require "rails_helper"

module BetterService
  module Workflows
    RSpec.describe "Execution" do
      let(:dummy_user_class) do
        Class.new do
          attr_accessor :id, :premium

          def initialize(id, premium: false)
            @id = id
            @premium = premium
          end

          def premium?
            @premium
          end
        end
      end

      let(:success_service_class) do
        Class.new(Services::Base) do
          schema do
            optional(:value).maybe(:integer)
          end

          process_with do |_data|
            { resource: { value: params[:value] || 42 } }
          end
        end
      end

      let(:failing_service_class) do
        Class.new(Services::Base) do
          schema do
            optional(:should_fail).maybe(:bool)
          end

          process_with do |_data|
            raise StandardError, "Service intentionally failed"
          end
        end
      end

      let(:user) { dummy_user_class.new(1) }

      describe "linear execution" do
        let(:linear_workflow_class) do
          success_svc = success_service_class

          Class.new(Base) do
            step :step_one,
                 with: success_svc,
                 input: ->(ctx) { { value: 1 } }

            step :step_two,
                 with: success_svc,
                 input: ->(ctx) { { value: 2 } }

            step :step_three,
                 with: success_svc,
                 input: ->(ctx) { { value: 3 } }
          end
        end

        it "executes all steps in order" do
          result = linear_workflow_class.new(user, params: {}).call

          expect(result[:success]).to be true
          expect(result[:metadata][:steps_executed]).to eq([ :step_one, :step_two, :step_three ])
        end

        it "stores step results in context" do
          result = linear_workflow_class.new(user, params: {}).call

          expect(result[:context].step_one).to eq({ value: 1 })
          expect(result[:context].step_two).to eq({ value: 2 })
          expect(result[:context].step_three).to eq({ value: 3 })
        end

        it "calculates workflow duration" do
          result = linear_workflow_class.new(user, params: {}).call

          expect(result[:metadata][:duration_ms]).to be_a(Numeric)
          expect(result[:metadata][:duration_ms]).to be >= 0
        end
      end

      describe "optional step execution" do
        let(:workflow_with_optional_step_class) do
          success_svc = success_service_class
          failing_svc = failing_service_class

          Class.new(Base) do
            step :required_step,
                 with: success_svc

            step :optional_step,
                 with: failing_svc,
                 optional: true

            step :final_step,
                 with: success_svc
          end
        end

        it "continues workflow when optional step fails" do
          result = workflow_with_optional_step_class.new(user, params: {}).call

          expect(result[:success]).to be true
          expect(result[:metadata][:steps_executed]).to include(:required_step)
          expect(result[:metadata][:steps_executed]).to include(:final_step)
          expect(result[:metadata][:steps_executed]).to include(:optional_step)
        end
      end

      describe "conditional step execution" do
        let(:workflow_with_conditional_step_class) do
          success_svc = success_service_class

          Class.new(Base) do
            step :always_runs,
                 with: success_svc

            step :conditional_step,
                 with: success_svc,
                 if: ->(ctx) { ctx.should_run }

            step :final_step,
                 with: success_svc
          end
        end

        it "executes conditional step when condition is true" do
          workflow = workflow_with_conditional_step_class.new(user, params: {})
          workflow.instance_variable_get(:@context).should_run = true

          result = workflow.call

          expect(result[:success]).to be true
          expect(result[:metadata][:steps_executed]).to include(:conditional_step)
          expect(result[:metadata][:steps_skipped]).to be_empty
        end

        it "skips conditional step when condition is false" do
          workflow = workflow_with_conditional_step_class.new(user, params: {})
          workflow.instance_variable_get(:@context).should_run = false

          result = workflow.call

          expect(result[:success]).to be true
          expect(result[:metadata][:steps_executed]).not_to include(:conditional_step)
          expect(result[:metadata][:steps_skipped]).to include(:conditional_step)
        end
      end

      describe "step failure handling" do
        let(:workflow_with_failing_step_class) do
          success_svc = success_service_class
          failing_svc = failing_service_class

          Class.new(Base) do
            step :first_step,
                 with: success_svc

            step :failing_step,
                 with: failing_svc

            step :unreachable_step,
                 with: success_svc
          end
        end

        it "raises StepExecutionError when required step fails" do
          expect {
            workflow_with_failing_step_class.new(user, params: {}).call
          }.to raise_error(Errors::Workflowable::Runtime::StepExecutionError) do |error|
            expect(error.code).to eq(:step_failed)
            expect(error.message).to include("Service intentionally failed")
          end
        end

        it "does not execute steps after failure" do
          workflow = workflow_with_failing_step_class.new(user, params: {})

          expect {
            workflow.call
          }.to raise_error(Errors::Workflowable::Runtime::StepExecutionError)

          executed_names = workflow.instance_variable_get(:@executed_steps).map(&:name)
          expect(executed_names).to include(:first_step)
          expect(executed_names).not_to include(:unreachable_step)
        end
      end

      describe "branching execution" do
        let(:workflow_with_branching_class) do
          success_svc = success_service_class

          Class.new(Base) do
            step :validate,
                 with: success_svc

            branch do
              on ->(ctx) { ctx.path == "A" } do
                step :path_a_step,
                     with: success_svc,
                     input: ->(ctx) { { value: 100 } }
              end

              on ->(ctx) { ctx.path == "B" } do
                step :path_b_step,
                     with: success_svc,
                     input: ->(ctx) { { value: 200 } }
              end

              otherwise do
                step :default_step,
                     with: success_svc,
                     input: ->(ctx) { { value: 0 } }
              end
            end

            step :finalize,
                 with: success_svc
          end
        end

        it "executes correct branch based on condition" do
          workflow = workflow_with_branching_class.new(user, params: {})
          workflow.instance_variable_get(:@context).path = "A"

          result = workflow.call

          expect(result[:success]).to be true
          expect(result[:metadata][:steps_executed]).to include(:path_a_step)
          expect(result[:metadata][:steps_executed]).not_to include(:path_b_step)
          expect(result[:metadata][:steps_executed]).not_to include(:default_step)
        end

        it "executes otherwise branch when no condition matches" do
          workflow = workflow_with_branching_class.new(user, params: {})
          workflow.instance_variable_get(:@context).path = "UNKNOWN"

          result = workflow.call

          expect(result[:success]).to be true
          expect(result[:metadata][:steps_executed]).to include(:default_step)
          expect(result[:metadata][:steps_executed]).not_to include(:path_a_step)
          expect(result[:metadata][:steps_executed]).not_to include(:path_b_step)
        end

        it "tracks branch decisions in metadata" do
          workflow = workflow_with_branching_class.new(user, params: {})
          workflow.instance_variable_get(:@context).path = "B"

          result = workflow.call

          expect(result[:metadata][:branches_taken]).to be_present
          expect(result[:metadata][:branches_taken].first).to include("on_2")
        end

        it "executes steps before and after branch" do
          workflow = workflow_with_branching_class.new(user, params: {})
          workflow.instance_variable_get(:@context).path = "A"

          result = workflow.call

          steps = result[:metadata][:steps_executed]
          expect(steps.first).to eq(:validate)
          expect(steps.last).to eq(:finalize)
        end
      end

      describe "error handling" do
        it "wraps unexpected errors in StepExecutionError" do
          success_svc = success_service_class

          workflow_class = Class.new(Base) do
            step :problematic,
                 with: Class.new(Services::Base) {
                   schema { }
                   process_with { raise NoMethodError, "Unexpected error" }
                 }
          end

          expect {
            workflow_class.new(user, params: {}).call
          }.to raise_error(Errors::Workflowable::Runtime::StepExecutionError) do |error|
            expect(error.code).to eq(:step_failed)
            expect(error.message).to include("Unexpected error")
          end
        end
      end
    end
  end
end
