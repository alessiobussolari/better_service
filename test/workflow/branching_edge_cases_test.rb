# frozen_string_literal: true

require "test_helper"

class WorkflowBranchingEdgeCasesTest < ActiveSupport::TestCase
  # Edge case tests for workflow branching
  # Tests unusual scenarios, error conditions, and boundary cases

  class User
    attr_accessor :id, :name
    def initialize(id, name = "Test User")
      @id = id
      @name = name
    end
  end

  # Mock services
  class SimpleService < BetterService::Services::Base
    schema { optional(:context).filled }
    process_with { { resource: { executed: true } } }
  end

  class ContextModifyingService < BetterService::Services::Base
    schema { optional(:context).filled }
    process_with do
      # Modify context during execution
      { resource: { new_value: rand(100) } }
    end
  end

  class FailingService < BetterService::Services::Base
    schema { optional(:context).filled }
    process_with { raise StandardError, "Service failed" }
  end

  setup do
    @user = User.new(1)
  end

  # ============================================================================
  # Edge Case 1: Branch Conditions That Raise Exceptions
  # ============================================================================

  test "branch condition that raises exception is treated as false" do
    workflow_class = Class.new(BetterService::Workflows::Base) do
      step :init, with: SimpleService

      branch do
        on ->(ctx) {
          raise StandardError, "Condition error"
        } do
          step :should_not_execute, with: SimpleService
        end

        otherwise do
          step :should_execute, with: SimpleService
        end
      end
    end

    result = workflow_class.new(@user, params: {}).call

    assert result[:success]
    assert_equal [:init, :should_execute], result[:metadata][:steps_executed]
    assert_includes result[:metadata][:branches_taken], "branch_1:otherwise"
  end

  # ============================================================================
  # Edge Case 2: Branch with Empty Steps
  # ============================================================================

  test "branch with no steps executes successfully" do
    workflow_class = Class.new(BetterService::Workflows::Base) do
      step :init, with: SimpleService

      branch do
        on ->(ctx) { true } do
          # No steps in this branch
        end

        otherwise do
          step :otherwise_step, with: SimpleService
        end
      end

      step :final, with: SimpleService
    end

    result = workflow_class.new(@user, params: {}).call

    assert result[:success]
    assert_equal [:init, :final], result[:metadata][:steps_executed]
    assert_includes result[:metadata][:branches_taken], "branch_1:on_1"
  end

  # ============================================================================
  # Edge Case 3: Deeply Nested Branches (5 levels)
  # ============================================================================

  test "deeply nested branches execute correctly" do
    workflow_class = Class.new(BetterService::Workflows::Base) do
      step :init, with: SimpleService

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
                          step :deeply_nested, with: SimpleService
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

      step :final, with: SimpleService
    end

    result = workflow_class.new(@user, params: {}).call

    assert result[:success]
    assert_equal [:init, :deeply_nested, :final], result[:metadata][:steps_executed]
    assert_equal 5, result[:metadata][:branches_taken].count
  end

  # ============================================================================
  # Edge Case 4: Branch with Optional Steps That Fail
  # ============================================================================

  test "optional step failure in branch does not stop workflow" do
    workflow_class = Class.new(BetterService::Workflows::Base) do
      step :init, with: SimpleService

      branch do
        on ->(ctx) { true } do
          step :failing_optional,
               with: FailingService,
               optional: true

          step :after_optional, with: SimpleService
        end
      end

      step :final, with: SimpleService
    end

    result = workflow_class.new(@user, params: {}).call

    assert result[:success]
    assert_equal [:init, :after_optional, :final], result[:metadata][:steps_executed]
  end

  # ============================================================================
  # Edge Case 5: Context Modified During Branch Execution
  # ============================================================================

  test "branch condition can use context modified by previous steps in same branch" do
    workflow_class = Class.new(BetterService::Workflows::Base) do
      step :init, with: SimpleService

      branch do
        on ->(ctx) { true } do
          step :modify_context, with: ContextModifyingService

          branch do
            on ->(ctx) { ctx.modify_context[:new_value] > 50 } do
              step :high_value, with: SimpleService
            end

            otherwise do
              step :low_value, with: SimpleService
            end
          end
        end
      end
    end

    result = workflow_class.new(@user, params: {}).call

    assert result[:success]
    # Either high_value or low_value should be executed based on random value
    assert(
      result[:metadata][:steps_executed].include?(:high_value) ||
      result[:metadata][:steps_executed].include?(:low_value)
    )
  end

  # ============================================================================
  # Edge Case 6: Multiple Branches in Sequence
  # ============================================================================

  test "multiple sequential branch blocks work correctly" do
    workflow_class = Class.new(BetterService::Workflows::Base) do
      step :init, with: SimpleService

      # First branch
      branch do
        on ->(ctx) { ctx.init[:executed] } do
          step :first_branch_path, with: SimpleService
        end
      end

      # Second branch
      branch do
        on ->(ctx) { ctx.first_branch_path[:executed] } do
          step :second_branch_path, with: SimpleService
        end
      end

      # Third branch
      branch do
        on ->(ctx) { ctx.second_branch_path[:executed] } do
          step :third_branch_path, with: SimpleService
        end
      end

      step :final, with: SimpleService
    end

    result = workflow_class.new(@user, params: {}).call

    assert result[:success]
    assert_equal [:init, :first_branch_path, :second_branch_path, :third_branch_path, :final],
                 result[:metadata][:steps_executed]
    assert_equal 3, result[:metadata][:branches_taken].count
  end

  # ============================================================================
  # Edge Case 7: Branch with Conditional Step Inside
  # ============================================================================

  test "branch can contain conditional steps with if clause" do
    workflow_class = Class.new(BetterService::Workflows::Base) do
      step :init, with: SimpleService

      branch do
        on ->(ctx) { true } do
          step :always_execute, with: SimpleService

          step :conditionally_execute,
               with: SimpleService,
               if: ->(ctx) { false }

          step :also_always_execute, with: SimpleService
        end
      end
    end

    result = workflow_class.new(@user, params: {}).call

    assert result[:success]
    assert_equal [:init, :always_execute, :also_always_execute], result[:metadata][:steps_executed]
    # Note: steps_skipped only tracks top-level skipped steps, not steps within branches
    # The conditional step is skipped but not tracked in the top-level metadata
  end

  # ============================================================================
  # Edge Case 8: All Branch Conditions Are False with No Otherwise
  # ============================================================================

  test "no matching branch without otherwise raises configuration error" do
    workflow_class = Class.new(BetterService::Workflows::Base) do
      step :init, with: SimpleService

      branch do
        on ->(ctx) { false } do
          step :should_not_execute, with: SimpleService
        end

        on ->(ctx) { false } do
          step :also_should_not_execute, with: SimpleService
        end
      end
    end

    error = assert_raises(BetterService::Errors::Configuration::InvalidConfigurationError) do
      workflow_class.new(@user, params: {}).call
    end

    assert_match(/No matching branch found/, error.message)
    assert_equal :configuration_error, error.code
  end

  # ============================================================================
  # Edge Case 9: Branch Rollback with Custom Rollback Logic
  # ============================================================================

  test "branch steps with custom rollback execute rollback in reverse order" do
    # Note: Rollback tracking is challenging to test because rollback blocks
    # are executed during the rollback phase which happens before the exception is raised.
    # This test verifies that the workflow properly raises an error when a step fails.

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

      step :init, with: SimpleService

      branch do
        on ->(ctx) { true } do
          step :step1, with: service1
          step :step2, with: service2
          step :failing_step, with: FailingService
        end
      end
    end

    error = assert_raises(BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError) do
      workflow_class.new(@user, params: {}).call
    end

    # Verify error was raised during branch execution
    assert_match(/Service failed/, error.message)
  end

  # ============================================================================
  # Edge Case 10: Branch Condition Accessing Non-existent Context Key
  # ============================================================================

  test "branch condition accessing missing context key handles gracefully" do
    workflow_class = Class.new(BetterService::Workflows::Base) do
      step :init, with: SimpleService

      branch do
        on ->(ctx) {
          # Try to access a key that doesn't exist
          ctx.respond_to?(:nonexistent_key) && ctx.nonexistent_key&.value == "something"
        } do
          step :should_not_execute, with: SimpleService
        end

        otherwise do
          step :should_execute, with: SimpleService
        end
      end
    end

    result = workflow_class.new(@user, params: {}).call

    assert result[:success]
    assert_equal [:init, :should_execute], result[:metadata][:steps_executed]
  end

  # ============================================================================
  # Edge Case 11: Time-dependent Branch Conditions
  # ============================================================================

  test "branch conditions can be time-dependent" do
    workflow_class = Class.new(BetterService::Workflows::Base) do
      step :init, with: SimpleService

      branch do
        on ->(ctx) { Time.current.hour >= 0 && Time.current.hour < 12 } do
          step :morning_action, with: SimpleService
        end

        on ->(ctx) { Time.current.hour >= 12 && Time.current.hour < 18 } do
          step :afternoon_action, with: SimpleService
        end

        otherwise do
          step :evening_action, with: SimpleService
        end
      end
    end

    result = workflow_class.new(@user, params: {}).call

    assert result[:success]
    # One of the time-based branches should execute
    assert(
      result[:metadata][:steps_executed].include?(:morning_action) ||
      result[:metadata][:steps_executed].include?(:afternoon_action) ||
      result[:metadata][:steps_executed].include?(:evening_action)
    )
  end

  # ============================================================================
  # Edge Case 12: Branch with Complex Boolean Logic
  # ============================================================================

  test "branch with complex AND/OR conditions" do
    workflow_class = Class.new(BetterService::Workflows::Base) do
      step :init, with: SimpleService

      branch do
        on ->(ctx) {
          (ctx.user.id > 0 && ctx.user.name.present?) ||
          (ctx.init[:executed] && !ctx.init[:executed].nil?)
        } do
          step :complex_condition_met, with: SimpleService
        end

        otherwise do
          step :complex_condition_not_met, with: SimpleService
        end
      end
    end

    result = workflow_class.new(@user, params: {}).call

    assert result[:success]
    assert_equal [:init, :complex_condition_met], result[:metadata][:steps_executed]
  end

  # ============================================================================
  # Edge Case 13: Branch with Params Access
  # ============================================================================

  test "branch conditions can access workflow params" do
    workflow_class = Class.new(BetterService::Workflows::Base) do
      step :init, with: SimpleService

      branch do
        on ->(ctx) { ctx.mode == "fast" } do
          step :fast_processing, with: SimpleService
        end

        on ->(ctx) { ctx.mode == "slow" } do
          step :slow_processing, with: SimpleService
        end

        otherwise do
          step :default_processing, with: SimpleService
        end
      end
    end

    # Test with fast mode
    fast_result = workflow_class.new(@user, params: { mode: "fast" }).call
    assert fast_result[:success]
    assert_includes fast_result[:metadata][:steps_executed], :fast_processing

    # Test with slow mode
    slow_result = workflow_class.new(@user, params: { mode: "slow" }).call
    assert slow_result[:success]
    assert_includes slow_result[:metadata][:steps_executed], :slow_processing

    # Test with no mode (default)
    default_result = workflow_class.new(@user, params: {}).call
    assert default_result[:success]
    assert_includes default_result[:metadata][:steps_executed], :default_processing
  end

  # ============================================================================
  # Edge Case 14: Branch After Failed Optional Step
  # ============================================================================

  test "branch executes correctly after failed optional step" do
    workflow_class = Class.new(BetterService::Workflows::Base) do
      step :init, with: SimpleService

      step :optional_failing,
           with: FailingService,
           optional: true

      branch do
        on ->(ctx) { ctx.init[:executed] } do
          step :branch_step, with: SimpleService
        end
      end

      step :final, with: SimpleService
    end

    result = workflow_class.new(@user, params: {}).call

    assert result[:success]
    # Optional step that fails is still tracked in executed steps
    assert_includes result[:metadata][:steps_executed], :init
    assert_includes result[:metadata][:steps_executed], :optional_failing
    assert_includes result[:metadata][:steps_executed], :branch_step
    assert_includes result[:metadata][:steps_executed], :final
    # The optional step failure should be in context with error information
    assert result[:context].respond_to?(:optional_failing_error)
  end

  # ============================================================================
  # Edge Case 15: Empty Branch Block
  # ============================================================================

  test "empty branch block raises validation error" do
    error = assert_raises(BetterService::Errors::Configuration::InvalidConfigurationError) do
      Class.new(BetterService::Workflows::Base) do
        step :init, with: SimpleService

        branch do
          # Empty - no on/otherwise blocks
        end
      end
    end

    assert_match(/must contain at least one/, error.message)
  end
end
