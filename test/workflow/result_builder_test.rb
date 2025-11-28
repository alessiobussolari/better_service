# frozen_string_literal: true

require "test_helper"

class BetterService::Workflows::ResultBuilderTest < ActiveSupport::TestCase
  # Test class that includes ResultBuilder
  class TestWorkflowWithResultBuilder
    include BetterService::Workflows::ResultBuilder

    attr_accessor :context, :branch_decisions, :start_time, :end_time

    def initialize
      @context = BetterService::Workflowable::Context.new(nil)
      @branch_decisions = []
    end

    def self.name
      "TestWorkflow"
    end

    # Expose private methods for testing
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

  setup do
    @builder = TestWorkflowWithResultBuilder.new
  end

  # =====================
  # build_success_result tests
  # =====================

  test "build_success_result returns success true" do
    @builder.start_time = Time.current
    @builder.end_time = Time.current + 0.1

    result = @builder.test_build_success_result

    assert result[:success]
    assert_equal "Workflow completed successfully", result[:message]
  end

  test "build_success_result includes workflow name in metadata" do
    @builder.start_time = Time.current
    @builder.end_time = Time.current

    result = @builder.test_build_success_result

    assert_equal "TestWorkflow", result[:metadata][:workflow]
  end

  test "build_success_result tracks executed steps" do
    @builder.start_time = Time.current
    @builder.end_time = Time.current

    result = @builder.test_build_success_result(
      steps_executed: [:step1, :step2, :step3]
    )

    assert_equal [:step1, :step2, :step3], result[:metadata][:steps_executed]
  end

  test "build_success_result tracks skipped steps" do
    @builder.start_time = Time.current
    @builder.end_time = Time.current

    result = @builder.test_build_success_result(
      steps_executed: [:step1],
      steps_skipped: [:step2, :step3]
    )

    assert_equal [:step1], result[:metadata][:steps_executed]
    assert_equal [:step2, :step3], result[:metadata][:steps_skipped]
  end

  test "build_success_result includes branch decisions when present" do
    @builder.start_time = Time.current
    @builder.end_time = Time.current
    @builder.branch_decisions = ["branch_1:on_1", "nested_branch_1:otherwise"]

    result = @builder.test_build_success_result

    assert_equal ["branch_1:on_1", "nested_branch_1:otherwise"], result[:metadata][:branches_taken]
  end

  test "build_success_result excludes branch decisions when empty" do
    @builder.start_time = Time.current
    @builder.end_time = Time.current
    @builder.branch_decisions = []

    result = @builder.test_build_success_result

    assert_not result[:metadata].key?(:branches_taken)
  end

  test "build_success_result includes context" do
    @builder.start_time = Time.current
    @builder.end_time = Time.current
    @builder.context.order = { id: 123 }

    result = @builder.test_build_success_result

    assert_equal @builder.context, result[:context]
    assert_equal({ id: 123 }, result[:context].order)
  end

  test "build_success_result calculates duration" do
    @builder.start_time = Time.current
    @builder.end_time = @builder.start_time + 0.5

    result = @builder.test_build_success_result

    assert_in_delta 500.0, result[:metadata][:duration_ms], 10.0
  end

  # =====================
  # build_failure_result tests
  # =====================

  test "build_failure_result returns success false" do
    @builder.start_time = Time.current
    @builder.end_time = Time.current

    result = @builder.test_build_failure_result

    assert_not result[:success]
  end

  test "build_failure_result uses provided message" do
    @builder.start_time = Time.current
    @builder.end_time = Time.current

    result = @builder.test_build_failure_result(message: "Custom error message")

    assert_equal "Custom error message", result[:error]
  end

  test "build_failure_result falls back to context errors message" do
    @builder.start_time = Time.current
    @builder.end_time = Time.current
    @builder.context.errors[:message] = "Context error message"

    result = @builder.test_build_failure_result

    assert_equal "Context error message", result[:error]
  end

  test "build_failure_result falls back to default message" do
    @builder.start_time = Time.current
    @builder.end_time = Time.current

    result = @builder.test_build_failure_result

    assert_equal "Workflow failed", result[:error]
  end

  test "build_failure_result includes failed step in metadata" do
    @builder.start_time = Time.current
    @builder.end_time = Time.current

    result = @builder.test_build_failure_result(
      failed_step: :payment_step,
      steps_executed: [:order_step]
    )

    assert_equal :payment_step, result[:metadata][:failed_step]
    assert_equal [:order_step], result[:metadata][:steps_executed]
  end

  test "build_failure_result excludes nil failed_step from metadata" do
    @builder.start_time = Time.current
    @builder.end_time = Time.current

    result = @builder.test_build_failure_result(failed_step: nil)

    assert_not result[:metadata].key?(:failed_step)
  end

  test "build_failure_result includes provided errors" do
    @builder.start_time = Time.current
    @builder.end_time = Time.current

    result = @builder.test_build_failure_result(
      errors: { payment: ["Card declined"] }
    )

    assert_equal({ payment: ["Card declined"] }, result[:errors])
  end

  test "build_failure_result falls back to context errors" do
    @builder.start_time = Time.current
    @builder.end_time = Time.current
    @builder.context.errors[:validation] = ["Invalid input"]

    result = @builder.test_build_failure_result

    assert @builder.context.errors[:validation].present?
  end

  test "build_failure_result includes branch decisions when present" do
    @builder.start_time = Time.current
    @builder.end_time = Time.current
    @builder.branch_decisions = ["branch_1:on_2"]

    result = @builder.test_build_failure_result

    assert_equal ["branch_1:on_2"], result[:metadata][:branches_taken]
  end

  # =====================
  # duration_ms tests
  # =====================

  test "duration_ms returns nil when start_time is nil" do
    @builder.start_time = nil
    @builder.end_time = Time.current

    assert_nil @builder.test_duration_ms
  end

  test "duration_ms returns nil when end_time is nil" do
    @builder.start_time = Time.current
    @builder.end_time = nil

    assert_nil @builder.test_duration_ms
  end

  test "duration_ms calculates correct milliseconds" do
    @builder.start_time = Time.current
    @builder.end_time = @builder.start_time + 1.5

    duration = @builder.test_duration_ms

    assert_in_delta 1500.0, duration, 1.0
  end

  test "duration_ms rounds to 2 decimal places" do
    @builder.start_time = Time.current
    @builder.end_time = @builder.start_time + 0.12345

    duration = @builder.test_duration_ms

    assert_equal 2, duration.to_s.split(".").last&.length || 0
  end
end
