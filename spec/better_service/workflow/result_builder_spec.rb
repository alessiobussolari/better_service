# frozen_string_literal: true

require "rails_helper"

module BetterService
  module Workflows
    RSpec.describe ResultBuilder do
      let(:test_workflow_class) do
        Class.new do
          include ResultBuilder

          attr_accessor :context, :branch_decisions, :start_time, :end_time

          def initialize
            @context = Workflowable::Context.new(nil)
            @branch_decisions = []
          end

          def self.name
            "TestWorkflow"
          end

          def test_build_success_result(**args)
            build_success_result(**args)
          end

          def test_build_failure_result(**args)
            build_failure_result(**args)
          end

          def test_duration_ms
            duration_ms
          end
        end
      end

      let(:builder) { test_workflow_class.new }

      describe "#build_success_result" do
        before do
          builder.start_time = Time.current
          builder.end_time = Time.current + 0.1
        end

        it "returns success true" do
          result = builder.test_build_success_result

          expect(result[:success]).to be true
          expect(result[:message]).to eq("Workflow completed successfully")
        end

        it "includes workflow name in metadata" do
          result = builder.test_build_success_result

          expect(result[:metadata][:workflow]).to eq("TestWorkflow")
        end

        it "tracks executed steps" do
          result = builder.test_build_success_result(
            steps_executed: [:step1, :step2, :step3]
          )

          expect(result[:metadata][:steps_executed]).to eq([:step1, :step2, :step3])
        end

        it "tracks skipped steps" do
          result = builder.test_build_success_result(
            steps_executed: [:step1],
            steps_skipped: [:step2, :step3]
          )

          expect(result[:metadata][:steps_executed]).to eq([:step1])
          expect(result[:metadata][:steps_skipped]).to eq([:step2, :step3])
        end

        it "includes branch decisions when present" do
          builder.branch_decisions = ["branch_1:on_1", "nested_branch_1:otherwise"]

          result = builder.test_build_success_result

          expect(result[:metadata][:branches_taken]).to eq(["branch_1:on_1", "nested_branch_1:otherwise"])
        end

        it "excludes branch decisions when empty" do
          builder.branch_decisions = []

          result = builder.test_build_success_result

          expect(result[:metadata]).not_to have_key(:branches_taken)
        end

        it "includes context" do
          builder.context.order = { id: 123 }

          result = builder.test_build_success_result

          expect(result[:context]).to eq(builder.context)
          expect(result[:context].order).to eq({ id: 123 })
        end

        it "calculates duration" do
          builder.start_time = Time.current
          builder.end_time = builder.start_time + 0.5

          result = builder.test_build_success_result

          expect(result[:metadata][:duration_ms]).to be_within(10.0).of(500.0)
        end
      end

      describe "#build_failure_result" do
        before do
          builder.start_time = Time.current
          builder.end_time = Time.current
        end

        it "returns success false" do
          result = builder.test_build_failure_result

          expect(result[:success]).to be false
        end

        it "uses provided message" do
          result = builder.test_build_failure_result(message: "Custom error message")

          expect(result[:error]).to eq("Custom error message")
        end

        it "falls back to context errors message" do
          builder.context.errors[:message] = "Context error message"

          result = builder.test_build_failure_result

          expect(result[:error]).to eq("Context error message")
        end

        it "falls back to default message" do
          result = builder.test_build_failure_result

          expect(result[:error]).to eq("Workflow failed")
        end

        it "includes failed step in metadata" do
          result = builder.test_build_failure_result(
            failed_step: :payment_step,
            steps_executed: [:order_step]
          )

          expect(result[:metadata][:failed_step]).to eq(:payment_step)
          expect(result[:metadata][:steps_executed]).to eq([:order_step])
        end

        it "excludes nil failed_step from metadata" do
          result = builder.test_build_failure_result(failed_step: nil)

          expect(result[:metadata]).not_to have_key(:failed_step)
        end

        it "includes provided errors" do
          result = builder.test_build_failure_result(
            errors: { payment: ["Card declined"] }
          )

          expect(result[:errors]).to eq({ payment: ["Card declined"] })
        end

        it "includes branch decisions when present" do
          builder.branch_decisions = ["branch_1:on_2"]

          result = builder.test_build_failure_result

          expect(result[:metadata][:branches_taken]).to eq(["branch_1:on_2"])
        end
      end

      describe "#duration_ms" do
        it "returns nil when start_time is nil" do
          builder.start_time = nil
          builder.end_time = Time.current

          expect(builder.test_duration_ms).to be_nil
        end

        it "returns nil when end_time is nil" do
          builder.start_time = Time.current
          builder.end_time = nil

          expect(builder.test_duration_ms).to be_nil
        end

        it "calculates correct milliseconds" do
          builder.start_time = Time.current
          builder.end_time = builder.start_time + 1.5

          duration = builder.test_duration_ms

          expect(duration).to be_within(1.0).of(1500.0)
        end

        it "rounds to 2 decimal places" do
          builder.start_time = Time.current
          builder.end_time = builder.start_time + 0.12345

          duration = builder.test_duration_ms

          expect(duration.to_s.split(".").last&.length || 0).to be <= 2
        end
      end
    end
  end
end
