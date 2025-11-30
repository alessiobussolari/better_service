# frozen_string_literal: true

require "rails_helper"

module BetterService
  module Workflowable
    RSpec.describe Step do
      let(:dummy_user_class) do
        Class.new do
          attr_accessor :id, :name

          def initialize(id, name)
            @id = id
            @name = name
          end
        end
      end

      let(:mock_service_class) do
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
            required(:value).filled(:integer)
          end

          process_with do |_data|
            raise StandardError, "Service failed"
          end
        end
      end

      let(:user) { dummy_user_class.new(1, "Test User") }
      let(:context) { Context.new(user) }

      describe "#call" do
        it "executes service and stores result in context" do
          step = described_class.new(
            name: :test_step,
            service_class: mock_service_class
          )

          result = step.call(context, user)

          expect(result[:success]).to be true
          expect(context.test_step).to eq({ value: 42 })
        end

        it "uses input mapper to build service params" do
          context.amount = 100

          step = described_class.new(
            name: :test_step,
            service_class: mock_service_class,
            input: ->(ctx) { { value: ctx.amount * 2 } }
          )

          result = step.call(context, user)

          expect(result[:success]).to be true
          expect(context.test_step).to eq({ value: 200 })
        end
      end

      describe "conditional execution" do
        it "skips step when condition returns false" do
          context.should_run = false

          step = described_class.new(
            name: :test_step,
            service_class: mock_service_class,
            condition: ->(ctx) { ctx.should_run }
          )

          result = step.call(context, user)

          expect(result[:success]).to be true
          expect(result[:skipped]).to be true
          expect(context.get(:test_step)).to be_nil
        end

        it "executes step when condition returns true" do
          context.should_run = true

          step = described_class.new(
            name: :test_step,
            service_class: mock_service_class,
            condition: ->(ctx) { ctx.should_run }
          )

          result = step.call(context, user)

          expect(result[:success]).to be true
          expect(result[:skipped]).to be_falsey
          expect(context.test_step).to eq({ value: 42 })
        end
      end

      describe "optional steps" do
        it "continues on failure when step is optional" do
          step = described_class.new(
            name: :failing_step,
            service_class: failing_service_class,
            optional: true
          )

          result = step.call(context, user, {})

          expect(result[:success]).to be true
          expect(result[:optional_failure]).to be true
          expect(context.get(:failing_step_error)).to be_present
        end

        it "returns failure when required step fails" do
          step = described_class.new(
            name: :failing_step,
            service_class: failing_service_class,
            optional: false
          )

          expect {
            step.call(context, user, {})
          }.to raise_error(Errors::Runtime::ValidationError) do |error|
            expect(error.code).to eq(:validation_failed)
          end
        end
      end

      describe "#rollback" do
        it "executes rollback block when provided" do
          rollback_executed = false

          step = described_class.new(
            name: :test_step,
            service_class: mock_service_class,
            rollback: ->(ctx) { rollback_executed = true }
          )

          step.rollback(context)

          expect(rollback_executed).to be true
        end

        it "propagates errors from rollback" do
          step = described_class.new(
            name: :test_step,
            service_class: mock_service_class,
            rollback: ->(ctx) { raise "Rollback error" }
          )

          expect {
            step.rollback(context)
          }.to raise_error(RuntimeError, "Rollback error")
        end
      end
    end
  end
end
