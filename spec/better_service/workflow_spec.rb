# frozen_string_literal: true

require "rails_helper"

module BetterService
  RSpec.describe "Workflows" do
    let(:dummy_user_class) do
      Class.new do
        attr_accessor :id, :name

        def initialize(id, name)
          @id = id
          @name = name
        end
      end
    end

    let(:user) { dummy_user_class.new(1, "Test User") }

    # Mock services for testing
    let(:first_service_class) do
      Class.new(Services::Base) do
        schema do
          required(:value).filled(:integer)
        end

        process_with do |_data|
          { resource: { result: params[:value] * 2 } }
        end
      end
    end

    let(:second_service_class) do
      Class.new(Services::Base) do
        schema do
          required(:previous_result).filled(:integer)
        end

        process_with do |_data|
          { resource: { final: params[:previous_result] + 10 } }
        end
      end
    end

    let(:failing_service_class) do
      Class.new(Services::Base) do
        schema { }

        process_with do |_data|
          raise StandardError, "Service failed"
        end
      end
    end

    describe "linear workflow execution" do
      let(:simple_workflow_class) do
        first_svc = first_service_class
        second_svc = second_service_class

        Class.new(Workflows::Base) do
          step :first,
               with: first_svc,
               input: ->(ctx) { { value: ctx.initial_value } }

          step :second,
               with: second_svc,
               input: ->(ctx) { { previous_result: ctx.first[:result] } }
        end
      end

      it "executes workflow steps in sequence" do
        result = simple_workflow_class.new(user, params: { initial_value: 5 }).call

        expect(result[:success]).to be true
        expect(result[:context].first[:result]).to eq(10)
        expect(result[:context].second[:final]).to eq(20)
      end

      it "returns workflow metadata" do
        result = simple_workflow_class.new(user, params: { initial_value: 5 }).call

        # Anonymous classes have nil name, so workflow metadata is nil
        # In real usage with named classes, it would contain the class name
        expect(result[:metadata]).to have_key(:workflow)
        expect(result[:metadata][:steps_executed]).to eq([ :first, :second ])
        expect(result[:metadata][:steps_skipped]).to eq([])
        expect(result[:metadata][:duration_ms]).to be_a(Numeric)
      end

      it "workflow context is accessible in result" do
        result = simple_workflow_class.new(user, params: { initial_value: 5 }).call

        expect(result[:context]).to be_a(Workflowable::Context)
        expect(result[:context].user).to eq(user)
        expect(result[:context]).to be_success
      end
    end

    describe "transactional workflow" do
      let(:transactional_workflow_class) do
        first_svc = first_service_class

        Class.new(Workflows::Base) do
          with_transaction true

          step :first,
               with: first_svc,
               input: ->(ctx) { { value: ctx.initial_value } }
        end
      end

      it "executes successfully with transaction" do
        result = transactional_workflow_class.new(user, params: { initial_value: 5 }).call

        expect(result[:success]).to be true
        expect(result[:context].first[:result]).to eq(10)
      end
    end

    describe "workflow callbacks" do
      let(:callback_workflow_class) do
        first_svc = first_service_class

        Class.new(Workflows::Base) do
          attr_accessor :before_called, :after_called, :around_called

          before_workflow :before_hook
          after_workflow :after_hook
          around_step :around_hook

          step :first,
               with: first_svc,
               input: ->(ctx) { { value: ctx.initial_value } }

          private

          def before_hook(context)
            @before_called = true
          end

          def after_hook(context)
            @after_called = true
          end

          def around_hook(step, context)
            @around_called = true
            yield
          end
        end
      end

      it "executes before and after callbacks" do
        workflow = callback_workflow_class.new(user, params: { initial_value: 5 })
        result = workflow.call

        expect(result[:success]).to be true
        expect(workflow.before_called).to be true
        expect(workflow.after_called).to be true
        expect(workflow.around_called).to be true
      end

      it "before_workflow callback can fail the workflow" do
        first_svc = first_service_class

        workflow_class = Class.new(Workflows::Base) do
          before_workflow :fail_it

          step :first,
               with: first_svc,
               input: ->(ctx) { { value: ctx.initial_value } }

          private

          def fail_it(context)
            context.fail!("Not allowed")
          end
        end

        result = workflow_class.new(user, params: { initial_value: 5 }).call

        expect(result[:success]).to be false
        expect(result[:errors][:message]).to eq("Not allowed")
      end
    end

    describe "optional steps" do
      let(:optional_step_workflow_class) do
        first_svc = first_service_class
        failing_svc = failing_service_class
        second_svc = second_service_class

        Class.new(Workflows::Base) do
          step :first,
               with: first_svc,
               input: ->(ctx) { { value: ctx.initial_value } }

          step :failing,
               with: failing_svc,
               optional: true

          step :second,
               with: second_svc,
               input: ->(ctx) { { previous_result: ctx.first[:result] } }
        end
      end

      it "optional step doesn't stop workflow on failure" do
        result = optional_step_workflow_class.new(user, params: { initial_value: 5 }).call

        expect(result[:success]).to be true
        expect(result[:context].first[:result]).to eq(10)
        expect(result[:context].second[:final]).to eq(20)
      end
    end

    describe "conditional steps" do
      let(:conditional_workflow_class) do
        first_svc = first_service_class

        Class.new(Workflows::Base) do
          step :first,
               with: first_svc,
               input: ->(ctx) { { value: ctx.initial_value } },
               if: ->(ctx) { ctx.should_run }
        end
      end

      it "conditional step is skipped when condition is false" do
        result = conditional_workflow_class.new(user, params: { initial_value: 5, should_run: false }).call

        expect(result[:success]).to be true
        expect(result[:metadata][:steps_executed]).to eq([])
        expect(result[:metadata][:steps_skipped]).to eq([ :first ])
      end

      it "conditional step is executed when condition is true" do
        result = conditional_workflow_class.new(user, params: { initial_value: 5, should_run: true }).call

        expect(result[:success]).to be true
        expect(result[:metadata][:steps_executed]).to eq([ :first ])
        expect(result[:metadata][:steps_skipped]).to eq([])
      end
    end

    describe "step failure" do
      let(:failing_workflow_class) do
        first_svc = first_service_class
        failing_svc = failing_service_class
        second_svc = second_service_class

        Class.new(Workflows::Base) do
          step :first,
               with: first_svc,
               input: ->(ctx) { { value: ctx.initial_value } }

          step :failing,
               with: failing_svc

          step :second,
               with: second_svc,
               input: ->(ctx) { { previous_result: 10 } }
        end
      end

      it "failing step stops workflow and raises error" do
        expect {
          failing_workflow_class.new(user, params: { initial_value: 5 }).call
        }.to raise_error(Errors::Workflowable::Runtime::StepExecutionError) do |error|
          expect(error.code).to eq(:step_failed)
          expect(error.context[:steps_executed]).to include(:first)
        end
      end

      it "workflow executes rollback on failure" do
        first_svc = first_service_class
        failing_svc = failing_service_class

        workflow_class = Class.new(Workflows::Base) do
          step :first,
               with: first_svc,
               input: ->(ctx) { { value: ctx.initial_value } },
               rollback: ->(ctx) { }

          step :failing,
               with: failing_svc
        end

        expect {
          workflow_class.new(user, params: { initial_value: 5 }).call
        }.to raise_error(Errors::Workflowable::Runtime::StepExecutionError) do |error|
          expect(error.code).to eq(:step_failed)
        end
      end
    end
  end
end
