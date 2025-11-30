# frozen_string_literal: true

require "rails_helper"

module BetterService
  module Workflows
    RSpec.describe "RollbackSupport" do
      let(:dummy_user_class) do
        Class.new do
          attr_accessor :id, :name

          def initialize(id, name: "Test User")
            @id = id
            @name = name
          end
        end
      end

      # Tracking module to record rollback calls
      let(:rollback_tracker) do
        Module.new do
          class << self
            attr_accessor :rollback_calls, :rollback_order

            def reset!
              @rollback_calls = []
              @rollback_order = []
            end

            def track(step_name)
              @rollback_calls ||= []
              @rollback_order ||= []
              @rollback_calls << step_name
              @rollback_order << step_name
            end
          end
        end
      end

      let(:success_service_class) do
        Class.new(Services::Base) do
          schema do
            optional(:value).maybe(:integer)
            optional(:step_name).maybe(:string)
          end

          process_with do |_data|
            { resource: { value: params[:value] || 42, step: params[:step_name] } }
          end
        end
      end

      let(:failing_service_class) do
        Class.new(Services::Base) do
          schema {}

          process_with do |_data|
            raise StandardError, "Service intentionally failed"
          end
        end
      end

      let(:user) { dummy_user_class.new(1) }

      before { rollback_tracker.reset! }

      describe "basic rollback" do
        it "rollback is called when workflow fails" do
          tracker = rollback_tracker
          success_svc = success_service_class
          failing_svc = failing_service_class

          workflow_class = Class.new(Base) do
            with_transaction true

            step :step_one,
                 with: success_svc,
                 input: ->(ctx) { { step_name: "one" } },
                 rollback: ->(ctx) { tracker.track(:step_one) }

            step :step_two,
                 with: success_svc,
                 input: ->(ctx) { { step_name: "two" } },
                 rollback: ->(ctx) { tracker.track(:step_two) }

            step :failing_step,
                 with: failing_svc

            step :unreachable,
                 with: success_svc,
                 rollback: ->(ctx) { tracker.track(:unreachable) }
          end

          expect {
            workflow_class.new(user, params: {}).call
          }.to raise_error(Errors::Workflowable::Runtime::StepExecutionError)

          expect(tracker.rollback_calls).to include(:step_one)
          expect(tracker.rollback_calls).to include(:step_two)
        end

        it "rollback executes in reverse order" do
          tracker = rollback_tracker
          success_svc = success_service_class
          failing_svc = failing_service_class

          workflow_class = Class.new(Base) do
            with_transaction true

            step :step_one,
                 with: success_svc,
                 rollback: ->(ctx) { tracker.track(:step_one) }

            step :step_two,
                 with: success_svc,
                 rollback: ->(ctx) { tracker.track(:step_two) }

            step :failing_step,
                 with: failing_svc
          end

          expect {
            workflow_class.new(user, params: {}).call
          }.to raise_error(Errors::Workflowable::Runtime::StepExecutionError)

          expect(tracker.rollback_order).to eq([:step_two, :step_one])
        end

        it "unreachable steps are not rolled back" do
          tracker = rollback_tracker
          success_svc = success_service_class
          failing_svc = failing_service_class

          workflow_class = Class.new(Base) do
            with_transaction true

            step :step_one,
                 with: success_svc,
                 rollback: ->(ctx) { tracker.track(:step_one) }

            step :failing_step,
                 with: failing_svc

            step :unreachable,
                 with: success_svc,
                 rollback: ->(ctx) { tracker.track(:unreachable) }
          end

          expect {
            workflow_class.new(user, params: {}).call
          }.to raise_error(Errors::Workflowable::Runtime::StepExecutionError)

          expect(tracker.rollback_calls).not_to include(:unreachable)
        end
      end

      describe "partial rollback" do
        it "only steps with rollback handlers are rolled back" do
          tracker = rollback_tracker
          success_svc = success_service_class
          failing_svc = failing_service_class

          workflow_class = Class.new(Base) do
            with_transaction true

            step :with_rollback,
                 with: success_svc,
                 rollback: ->(ctx) { tracker.track(:with_rollback) }

            step :without_rollback,
                 with: success_svc

            step :another_with_rollback,
                 with: success_svc,
                 rollback: ->(ctx) { tracker.track(:another_with_rollback) }

            step :failing,
                 with: failing_svc
          end

          expect {
            workflow_class.new(user, params: {}).call
          }.to raise_error(Errors::Workflowable::Runtime::StepExecutionError)

          expect(tracker.rollback_calls).to include(:with_rollback)
          expect(tracker.rollback_calls).to include(:another_with_rollback)
        end

        it "steps without rollback are silently skipped during rollback" do
          tracker = rollback_tracker
          success_svc = success_service_class
          failing_svc = failing_service_class

          workflow_class = Class.new(Base) do
            with_transaction true

            step :with_rollback,
                 with: success_svc,
                 rollback: ->(ctx) { tracker.track(:with_rollback) }

            step :without_rollback,
                 with: success_svc

            step :failing,
                 with: failing_svc
          end

          expect {
            workflow_class.new(user, params: {}).call
          }.to raise_error(Errors::Workflowable::Runtime::StepExecutionError)

          expect(tracker.rollback_calls.count).to be >= 1
        end
      end

      describe "failing rollback" do
        it "failing rollback raises RollbackError" do
          success_svc = success_service_class
          failing_svc = failing_service_class

          workflow_class = Class.new(Base) do
            with_transaction true

            step :first_step,
                 with: success_svc,
                 rollback: ->(ctx) { raise StandardError, "Rollback failed!" }

            step :failing_step,
                 with: failing_svc
          end

          expect {
            workflow_class.new(user, params: {}).call
          }.to raise_error(Errors::Workflowable::Runtime::RollbackError) do |error|
            expect(error.code).to eq(:rollback_failed)
            expect(error.message).to include("Rollback failed")
            expect(error.message).to include("first_step")
          end
        end

        it "failing rollback includes context information" do
          success_svc = success_service_class
          failing_svc = failing_service_class

          workflow_class = Class.new(Base) do
            with_transaction true

            step :first_step,
                 with: success_svc,
                 rollback: ->(ctx) { raise StandardError, "Rollback failed!" }

            step :failing_step,
                 with: failing_svc
          end

          expect {
            workflow_class.new(user, params: {}).call
          }.to raise_error(Errors::Workflowable::Runtime::RollbackError) do |error|
            # Anonymous classes have nil name, so workflow context may be nil
            expect(error.context).to have_key(:workflow)
            expect(error.context[:step]).to eq(:first_step)
          end
        end

        it "failing rollback preserves original error" do
          success_svc = success_service_class
          failing_svc = failing_service_class

          workflow_class = Class.new(Base) do
            with_transaction true

            step :first_step,
                 with: success_svc,
                 rollback: ->(ctx) { raise StandardError, "Rollback failed!" }

            step :failing_step,
                 with: failing_svc
          end

          expect {
            workflow_class.new(user, params: {}).call
          }.to raise_error(Errors::Workflowable::Runtime::RollbackError) do |error|
            expect(error.original_error).to be_a(StandardError)
            expect(error.original_error.message).to eq("Rollback failed!")
          end
        end
      end

      describe "context in rollback" do
        it "rollback has access to context data" do
          tracker = rollback_tracker
          success_svc = success_service_class
          failing_svc = failing_service_class

          workflow_class = Class.new(Base) do
            with_transaction true

            step :create_order,
                 with: success_svc,
                 input: ->(ctx) { { value: 100 } },
                 rollback: ->(ctx) {
                   tracker.track(:create_order)
                   ctx.rollback_data = { order_value: ctx.create_order[:value] }
                 }

            step :failing_step,
                 with: failing_svc
          end

          workflow = workflow_class.new(user, params: {})

          expect {
            workflow.call
          }.to raise_error(Errors::Workflowable::Runtime::StepExecutionError)

          expect(tracker.rollback_calls).to include(:create_order)

          context = workflow.instance_variable_get(:@context)
          expect(context.rollback_data).to eq({ order_value: 100 })
        end
      end

      describe "successful workflow without rollback" do
        it "successful workflow does not trigger rollback" do
          tracker = rollback_tracker
          success_svc = success_service_class

          workflow_class = Class.new(Base) do
            with_transaction true

            step :step_one,
                 with: success_svc,
                 rollback: ->(ctx) { tracker.track(:step_one) }

            step :step_two,
                 with: success_svc,
                 rollback: ->(ctx) { tracker.track(:step_two) }
          end

          result = workflow_class.new(user, params: {}).call

          expect(result[:success]).to be true
          expect(tracker.rollback_calls).to be_empty
        end
      end

      describe "rollback continues for all steps" do
        it "rollback continues for all steps even with first step having no rollback" do
          tracker = rollback_tracker
          success_svc = success_service_class
          failing_svc = failing_service_class

          workflow_class = Class.new(Base) do
            with_transaction true

            step :no_rollback_step,
                 with: success_svc

            step :with_rollback,
                 with: success_svc,
                 rollback: ->(ctx) { tracker.track(:with_rollback) }

            step :failing,
                 with: failing_svc
          end

          expect {
            workflow_class.new(user, params: {}).call
          }.to raise_error(Errors::Workflowable::Runtime::StepExecutionError)

          expect(tracker.rollback_calls).to include(:with_rollback)
        end
      end

      describe "executed_steps tracking" do
        it "executed_steps tracks only executed steps" do
          tracker = rollback_tracker
          success_svc = success_service_class
          failing_svc = failing_service_class

          workflow_class = Class.new(Base) do
            with_transaction true

            step :step_one,
                 with: success_svc,
                 rollback: ->(ctx) { tracker.track(:step_one) }

            step :step_two,
                 with: success_svc,
                 rollback: ->(ctx) { tracker.track(:step_two) }

            step :failing_step,
                 with: failing_svc

            step :unreachable,
                 with: success_svc,
                 rollback: ->(ctx) { tracker.track(:unreachable) }
          end

          workflow = workflow_class.new(user, params: {})

          expect {
            workflow.call
          }.to raise_error(Errors::Workflowable::Runtime::StepExecutionError)

          executed_steps = workflow.instance_variable_get(:@executed_steps)
          executed_names = executed_steps.map(&:name)

          expect(executed_names).to include(:step_one)
          expect(executed_names).to include(:step_two)
          expect(executed_names).not_to include(:failing_step)
          expect(executed_names).not_to include(:unreachable)
        end
      end

      describe "rollback with branching" do
        it "rollback only affects executed steps, not other branches" do
          tracker = rollback_tracker
          success_svc = success_service_class
          failing_svc = failing_service_class

          workflow_class = Class.new(Base) do
            with_transaction true

            step :common_step,
                 with: success_svc,
                 rollback: ->(ctx) { tracker.track(:common_step) }

            branch do
              on ->(ctx) { ctx.path == "A" } do
                step :path_a_step,
                     with: success_svc,
                     rollback: ->(ctx) { tracker.track(:path_a_step) }

                step :path_a_fail,
                     with: failing_svc
              end

              on ->(ctx) { ctx.path == "B" } do
                step :path_b_step,
                     with: success_svc,
                     rollback: ->(ctx) { tracker.track(:path_b_step) }
              end
            end
          end

          workflow = workflow_class.new(user, params: {})
          workflow.instance_variable_get(:@context).path = "A"

          expect {
            workflow.call
          }.to raise_error(Errors::Workflowable::Runtime::StepExecutionError)

          expect(tracker.rollback_calls).not_to include(:path_b_step)
        end
      end
    end
  end
end
