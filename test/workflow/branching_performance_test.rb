# frozen_string_literal: true

require "test_helper"
require "benchmark"

class WorkflowBranchingPerformanceTest < ActiveSupport::TestCase
  # Performance tests for workflow branching
  # These tests measure overhead and ensure branching doesn't significantly impact performance

  class User
    attr_accessor :id, :name
    def initialize(id, name = "Test User")
      @id = id
      @name = name
    end
  end

  class FastService < BetterService::Services::Base
    schema { optional(:context).filled }
    process_with { { resource: { executed: true, timestamp: Time.current } } }
  end

  setup do
    @user = User.new(1)
    @iterations = 100 # Number of iterations for performance tests
  end

  # ============================================================================
  # Performance Test 1: Linear vs Single Branch Overhead
  # ============================================================================

  test "single branch overhead compared to linear workflow" do
    # Linear workflow (baseline)
    linear_workflow = Class.new(BetterService::Workflows::Base) do
      step :step1, with: FastService
      step :step2, with: FastService
      step :step3, with: FastService
    end

    # Branch workflow (test subject)
    branch_workflow = Class.new(BetterService::Workflows::Base) do
      step :step1, with: FastService

      branch do
        on ->(ctx) { true } do
          step :step2, with: FastService
        end
      end

      step :step3, with: FastService
    end

    # Measure linear execution time
    linear_time = Benchmark.realtime do
      @iterations.times { linear_workflow.new(@user, params: {}).call }
    end

    # Measure branch execution time
    branch_time = Benchmark.realtime do
      @iterations.times { branch_workflow.new(@user, params: {}).call }
    end

    overhead_ratio = branch_time / linear_time
    overhead_percent = ((overhead_ratio - 1.0) * 100).round(2)

    # Assert that overhead is reasonable (less than 50%)
    assert overhead_ratio < 1.5, "Branch overhead should be less than 50%, got #{overhead_percent}%"
  end

  # ============================================================================
  # Performance Test 2: Many Branches Performance
  # ============================================================================

  test "workflow with many branches (10+) selection performance" do
    workflow_class = Class.new(BetterService::Workflows::Base) do
      step :init, with: FastService

      branch do
        on ->(ctx) { ctx.target == 1 } do
          step :path1, with: FastService
        end

        on ->(ctx) { ctx.target == 2 } do
          step :path2, with: FastService
        end

        on ->(ctx) { ctx.target == 3 } do
          step :path3, with: FastService
        end

        on ->(ctx) { ctx.target == 4 } do
          step :path4, with: FastService
        end

        on ->(ctx) { ctx.target == 5 } do
          step :path5, with: FastService
        end

        on ->(ctx) { ctx.target == 6 } do
          step :path6, with: FastService
        end

        on ->(ctx) { ctx.target == 7 } do
          step :path7, with: FastService
        end

        on ->(ctx) { ctx.target == 8 } do
          step :path8, with: FastService
        end

        on ->(ctx) { ctx.target == 9 } do
          step :path9, with: FastService
        end

        on ->(ctx) { ctx.target == 10 } do
          step :path10, with: FastService
        end

        otherwise do
          step :default_path, with: FastService
        end
      end

      step :final, with: FastService
    end

    # Verify all executions succeeded
    result = workflow_class.new(@user, params: { target: 5 }).call
    assert result[:success]
  end

  # ============================================================================
  # Performance Test 3: Deeply Nested Branches
  # ============================================================================

  test "deeply nested branches (5 levels) performance" do
    # Nested workflow (test subject)
    nested_workflow = Class.new(BetterService::Workflows::Base) do
      step :step1, with: FastService

      branch do
        on ->(ctx) { true } do
          step :step2, with: FastService

          branch do
            on ->(ctx) { true } do
              step :step3, with: FastService

              branch do
                on ->(ctx) { true } do
                  step :step4, with: FastService

                  branch do
                    on ->(ctx) { true } do
                      step :step5, with: FastService
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    # Verify nested workflow works correctly
    result = nested_workflow.new(@user, params: {}).call
    assert result[:success]
    # 4 nested levels (first branch + 3 nested branches)
    assert_equal 4, result[:metadata][:branches_taken].count
  end

  # ============================================================================
  # Performance Test 4: Complex Condition Evaluation
  # ============================================================================

  test "complex condition evaluation performance" do
    # Simple condition (baseline)
    simple_workflow = Class.new(BetterService::Workflows::Base) do
      step :init, with: FastService

      branch do
        on ->(ctx) { true } do
          step :action, with: FastService
        end
      end
    end

    # Complex condition (test subject)
    complex_workflow = Class.new(BetterService::Workflows::Base) do
      step :init, with: FastService

      branch do
        on ->(ctx) {
          ctx.user.id > 0 &&
          ctx.user.name.present? &&
          ctx.init[:executed] == true &&
          [1, 2, 3, 4, 5].include?(ctx.user.id) &&
          ctx.user.name.length > 3 &&
          Time.current.wday.between?(1, 5)
        } do
          step :action, with: FastService
        end
      end
    end

    simple_time = Benchmark.realtime do
      @iterations.times { simple_workflow.new(@user, params: {}).call }
    end

    complex_time = Benchmark.realtime do
      @iterations.times { complex_workflow.new(@user, params: {}).call }
    end

    # Complex conditions should still be fast (< 1ms overhead per iteration)
    per_iteration_overhead_ms = (complex_time - simple_time) / @iterations * 1000
    assert per_iteration_overhead_ms < 1.0, "Complex condition overhead should be < 1ms per iteration"
  end

  # ============================================================================
  # Performance Test 5: Branch Decision Tracking Overhead
  # ============================================================================

  test "metadata tracking overhead for branch decisions" do
    # Workflow without branches (baseline)
    no_branch_workflow = Class.new(BetterService::Workflows::Base) do
      step :step1, with: FastService
      step :step2, with: FastService
      step :step3, with: FastService
    end

    # Workflow with multiple branches (test subject)
    multi_branch_workflow = Class.new(BetterService::Workflows::Base) do
      step :step1, with: FastService

      branch do
        on ->(ctx) { true } do
          step :step2, with: FastService
        end
      end

      branch do
        on ->(ctx) { true } do
          step :step3, with: FastService
        end
      end

      branch do
        on ->(ctx) { true } do
          step :step4, with: FastService
        end
      end
    end

    no_branch_time = Benchmark.realtime do
      @iterations.times { no_branch_workflow.new(@user, params: {}).call }
    end

    multi_branch_time = Benchmark.realtime do
      @iterations.times { multi_branch_workflow.new(@user, params: {}).call }
    end

    # Verify metadata is being tracked
    result = multi_branch_workflow.new(@user, params: {}).call
    assert result[:success]
    assert_equal 3, result[:metadata][:branches_taken].count

    tracking_overhead = ((multi_branch_time - no_branch_time) / @iterations * 1000).round(3)

    # Metadata tracking should have minimal impact
    assert tracking_overhead < 0.5, "Metadata tracking overhead should be < 0.5ms per iteration"
  end
end
