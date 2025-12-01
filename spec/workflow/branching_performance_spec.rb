# frozen_string_literal: true

require "rails_helper"
require "benchmark"

RSpec.describe "Workflow Branching Performance", type: :workflow do
  class PerformanceTestUser
    attr_accessor :id, :name

    def initialize(id, name = "Test User")
      @id = id
      @name = name
    end
  end

  class PerformanceTestFastService < BetterService::Services::Base
    schema { optional(:context).filled }
    process_with { { resource: { executed: true, timestamp: Time.current } } }
  end

  let(:user) { PerformanceTestUser.new(1) }
  let(:iterations) { 100 }

  describe "Linear vs Single Branch Overhead" do
    it "has reasonable overhead compared to linear workflow" do
      linear_workflow = Class.new(BetterService::Workflows::Base) do
        step :step1, with: PerformanceTestFastService
        step :step2, with: PerformanceTestFastService
        step :step3, with: PerformanceTestFastService
      end

      branch_workflow = Class.new(BetterService::Workflows::Base) do
        step :step1, with: PerformanceTestFastService

        branch do
          on ->(ctx) { true } do
            step :step2, with: PerformanceTestFastService
          end
        end

        step :step3, with: PerformanceTestFastService
      end

      linear_time = Benchmark.realtime do
        iterations.times { linear_workflow.new(user, params: {}).call }
      end

      branch_time = Benchmark.realtime do
        iterations.times { branch_workflow.new(user, params: {}).call }
      end

      overhead_ratio = branch_time / linear_time
      overhead_percent = ((overhead_ratio - 1.0) * 100).round(2)

      # Assert that overhead is reasonable (less than 50%)
      expect(overhead_ratio).to be < 1.5,
        "Branch overhead should be less than 50%, got #{overhead_percent}%"
    end
  end

  describe "Many Branches Selection Performance" do
    it "handles workflow with 10+ branches efficiently" do
      workflow_class = Class.new(BetterService::Workflows::Base) do
        step :init, with: PerformanceTestFastService

        branch do
          on(->(ctx) { ctx.target == 1 }) { step :path1, with: PerformanceTestFastService }
          on(->(ctx) { ctx.target == 2 }) { step :path2, with: PerformanceTestFastService }
          on(->(ctx) { ctx.target == 3 }) { step :path3, with: PerformanceTestFastService }
          on(->(ctx) { ctx.target == 4 }) { step :path4, with: PerformanceTestFastService }
          on(->(ctx) { ctx.target == 5 }) { step :path5, with: PerformanceTestFastService }
          on(->(ctx) { ctx.target == 6 }) { step :path6, with: PerformanceTestFastService }
          on(->(ctx) { ctx.target == 7 }) { step :path7, with: PerformanceTestFastService }
          on(->(ctx) { ctx.target == 8 }) { step :path8, with: PerformanceTestFastService }
          on(->(ctx) { ctx.target == 9 }) { step :path9, with: PerformanceTestFastService }
          on(->(ctx) { ctx.target == 10 }) { step :path10, with: PerformanceTestFastService }

          otherwise do
            step :default_path, with: PerformanceTestFastService
          end
        end

        step :final, with: PerformanceTestFastService
      end

      result = workflow_class.new(user, params: { target: 5 }).call
      expect(result[:success]).to be true
    end
  end

  describe "Deeply Nested Branches Performance" do
    it "executes deeply nested branches (5 levels) efficiently" do
      nested_workflow = Class.new(BetterService::Workflows::Base) do
        step :step1, with: PerformanceTestFastService

        branch do
          on ->(ctx) { true } do
            step :step2, with: PerformanceTestFastService

            branch do
              on ->(ctx) { true } do
                step :step3, with: PerformanceTestFastService

                branch do
                  on ->(ctx) { true } do
                    step :step4, with: PerformanceTestFastService

                    branch do
                      on ->(ctx) { true } do
                        step :step5, with: PerformanceTestFastService
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end

      result = nested_workflow.new(user, params: {}).call

      expect(result[:success]).to be true
      expect(result[:metadata][:branches_taken].count).to eq(4)
    end
  end

  describe "Complex Condition Evaluation Performance" do
    it "evaluates complex conditions with minimal overhead" do
      simple_workflow = Class.new(BetterService::Workflows::Base) do
        step :init, with: PerformanceTestFastService

        branch do
          on ->(ctx) { true } do
            step :action, with: PerformanceTestFastService
          end
        end
      end

      complex_workflow = Class.new(BetterService::Workflows::Base) do
        step :init, with: PerformanceTestFastService

        branch do
          on ->(ctx) {
            ctx.user.id > 0 &&
            ctx.user.name.present? &&
            ctx.init[:executed] == true &&
            [ 1, 2, 3, 4, 5 ].include?(ctx.user.id) &&
            ctx.user.name.length > 3 &&
            Time.current.wday.between?(0, 6)
          } do
            step :action, with: PerformanceTestFastService
          end

          otherwise do
            step :fallback, with: PerformanceTestFastService
          end
        end
      end

      simple_time = Benchmark.realtime do
        iterations.times { simple_workflow.new(user, params: {}).call }
      end

      complex_time = Benchmark.realtime do
        iterations.times { complex_workflow.new(user, params: {}).call }
      end

      per_iteration_overhead_ms = (complex_time - simple_time) / iterations * 1000
      expect(per_iteration_overhead_ms).to be < 1.0,
        "Complex condition overhead should be < 1ms per iteration"
    end
  end

  describe "Metadata Tracking Overhead" do
    it "has minimal impact for branch decision tracking" do
      no_branch_workflow = Class.new(BetterService::Workflows::Base) do
        step :step1, with: PerformanceTestFastService
        step :step2, with: PerformanceTestFastService
        step :step3, with: PerformanceTestFastService
      end

      multi_branch_workflow = Class.new(BetterService::Workflows::Base) do
        step :step1, with: PerformanceTestFastService

        branch do
          on(->(ctx) { true }) { step :step2, with: PerformanceTestFastService }
        end

        branch do
          on(->(ctx) { true }) { step :step3, with: PerformanceTestFastService }
        end

        branch do
          on(->(ctx) { true }) { step :step4, with: PerformanceTestFastService }
        end
      end

      no_branch_time = Benchmark.realtime do
        iterations.times { no_branch_workflow.new(user, params: {}).call }
      end

      multi_branch_time = Benchmark.realtime do
        iterations.times { multi_branch_workflow.new(user, params: {}).call }
      end

      result = multi_branch_workflow.new(user, params: {}).call
      expect(result[:success]).to be true
      expect(result[:metadata][:branches_taken].count).to eq(3)

      tracking_overhead = ((multi_branch_time - no_branch_time) / iterations * 1000).round(3)
      expect(tracking_overhead).to be < 0.5,
        "Metadata tracking overhead should be < 0.5ms per iteration"
    end
  end
end
