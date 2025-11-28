# frozen_string_literal: true

require "test_helper"

class BetterService::WorkflowBranchTest < ActiveSupport::TestCase
  class User
    attr_accessor :id, :account_type, :premium
    def initialize(id, account_type: "basic", premium: false)
      @id = id
      @account_type = account_type
      @premium = premium
    end
  end

  # Mock services for testing
  class ValidateService < BetterService::Services::Base
    schema do
      required(:user_id).filled(:integer)
    end

    process_with do |data|
      { resource: { user_id: params[:user_id], validated: true } }
    end
  end

  class PremiumService < BetterService::Services::Base
    schema do
      optional(:context).filled
    end

    process_with do |data|
      { resource: { feature: "premium", executed: true } }
    end
  end

  class BasicService < BetterService::Services::Base
    schema do
      optional(:context).filled
    end

    process_with do |data|
      { resource: { feature: "basic", executed: true } }
    end
  end

  class EnterpriseService < BetterService::Services::Base
    schema do
      optional(:context).filled
    end

    process_with do |data|
      { resource: { feature: "enterprise", executed: true } }
    end
  end

  class DefaultService < BetterService::Services::Base
    schema do
      optional(:context).filled
    end

    process_with do |data|
      { resource: { feature: "default", executed: true } }
    end
  end

  class FailingService < BetterService::Services::Base
    schema do
      optional(:context).filled
    end

    process_with do |data|
      raise StandardError, "Service failed"
    end
  end

  class FinalService < BetterService::Services::Base
    schema do
      optional(:context).filled
    end

    process_with do |data|
      { resource: { final: true } }
    end
  end

  # Test workflows

  class SimpleBranchWorkflow < BetterService::Workflows::Base
    step :validate,
         with: ValidateService,
         input: ->(ctx) { { user_id: ctx.user_id } }

    branch do
      on ->(ctx) { ctx.user.premium } do
        step :premium_feature,
             with: PremiumService
      end

      otherwise do
        step :basic_feature,
             with: BasicService
      end
    end

    step :finalize,
         with: FinalService
  end

  class MultiBranchWorkflow < BetterService::Workflows::Base
    step :validate,
         with: ValidateService,
         input: ->(ctx) { { user_id: ctx.user_id } }

    branch do
      on ->(ctx) { ctx.user.account_type == "enterprise" } do
        step :enterprise_feature,
             with: EnterpriseService
      end

      on ->(ctx) { ctx.user.account_type == "premium" } do
        step :premium_feature,
             with: PremiumService
      end

      on ->(ctx) { ctx.user.account_type == "basic" } do
        step :basic_feature,
             with: BasicService
      end

      otherwise do
        step :default_feature,
             with: DefaultService
      end
    end

    step :finalize,
         with: FinalService
  end

  class NestedBranchWorkflow < BetterService::Workflows::Base
    step :validate,
         with: ValidateService,
         input: ->(ctx) { { user_id: ctx.user_id } }

    branch do
      on ->(ctx) { ctx.user.account_type == "premium" } do
        step :premium_feature,
             with: PremiumService

        branch do
          on ->(ctx) { ctx.user.premium } do
            step :premium_nested,
                 with: PremiumService
          end

          otherwise do
            step :basic_nested,
                 with: BasicService
          end
        end
      end

      otherwise do
        step :basic_feature,
             with: BasicService
      end
    end

    step :finalize,
         with: FinalService
  end

  class FailingBranchWorkflow < BetterService::Workflows::Base
    step :validate,
         with: ValidateService,
         input: ->(ctx) { { user_id: ctx.user_id } }

    branch do
      on ->(ctx) { ctx.user.premium } do
        step :failing_step,
             with: FailingService
      end

      otherwise do
        step :basic_feature,
             with: BasicService
      end
    end

    step :finalize,
         with: FinalService
  end

  class NoBranchMatchWorkflow < BetterService::Workflows::Base
    step :validate,
         with: ValidateService,
         input: ->(ctx) { { user_id: ctx.user_id } }

    branch do
      on ->(ctx) { ctx.user.account_type == "nonexistent" } do
        step :premium_feature,
             with: PremiumService
      end
    end

    step :finalize,
         with: FinalService
  end

  # Tests

  test "simple branch takes first path when condition is true" do
    user = User.new(1, premium: true)
    workflow = SimpleBranchWorkflow.new(user, params: { user_id: 1 })

    result = workflow.call

    assert result[:success]
    assert_equal [:validate, :premium_feature, :finalize], result[:metadata][:steps_executed]
    assert_includes result[:metadata][:branches_taken], "branch_1:on_1"
    assert_equal "premium", result[:context].premium_feature[:feature]
  end

  test "simple branch takes otherwise path when condition is false" do
    user = User.new(1, premium: false)
    workflow = SimpleBranchWorkflow.new(user, params: { user_id: 1 })

    result = workflow.call

    assert result[:success]
    assert_equal [:validate, :basic_feature, :finalize], result[:metadata][:steps_executed]
    assert_includes result[:metadata][:branches_taken], "branch_1:otherwise"
    assert_equal "basic", result[:context].basic_feature[:feature]
  end

  test "multi-branch takes first matching path" do
    user = User.new(1, account_type: "enterprise")
    workflow = MultiBranchWorkflow.new(user, params: { user_id: 1 })

    result = workflow.call

    assert result[:success]
    assert_equal [:validate, :enterprise_feature, :finalize], result[:metadata][:steps_executed]
    assert_includes result[:metadata][:branches_taken], "branch_1:on_1"
    assert_equal "enterprise", result[:context].enterprise_feature[:feature]
  end

  test "multi-branch takes second matching path" do
    user = User.new(1, account_type: "premium")
    workflow = MultiBranchWorkflow.new(user, params: { user_id: 1 })

    result = workflow.call

    assert result[:success]
    assert_equal [:validate, :premium_feature, :finalize], result[:metadata][:steps_executed]
    assert_includes result[:metadata][:branches_taken], "branch_1:on_2"
    assert_equal "premium", result[:context].premium_feature[:feature]
  end

  test "multi-branch takes third matching path" do
    user = User.new(1, account_type: "basic")
    workflow = MultiBranchWorkflow.new(user, params: { user_id: 1 })

    result = workflow.call

    assert result[:success]
    assert_equal [:validate, :basic_feature, :finalize], result[:metadata][:steps_executed]
    assert_includes result[:metadata][:branches_taken], "branch_1:on_3"
    assert_equal "basic", result[:context].basic_feature[:feature]
  end

  test "multi-branch takes otherwise path when no condition matches" do
    user = User.new(1, account_type: "unknown")
    workflow = MultiBranchWorkflow.new(user, params: { user_id: 1 })

    result = workflow.call

    assert result[:success]
    assert_equal [:validate, :default_feature, :finalize], result[:metadata][:steps_executed]
    assert_includes result[:metadata][:branches_taken], "branch_1:otherwise"
    assert_equal "default", result[:context].default_feature[:feature]
  end

  test "nested branches work correctly" do
    user = User.new(1, account_type: "premium", premium: true)
    workflow = NestedBranchWorkflow.new(user, params: { user_id: 1 })

    result = workflow.call

    assert result[:success]
    assert_equal [:validate, :premium_feature, :premium_nested, :finalize], result[:metadata][:steps_executed]
    assert_equal 2, result[:metadata][:branches_taken].count
    assert_includes result[:metadata][:branches_taken], "branch_1:on_1"
  end

  test "nested branch takes otherwise in nested level" do
    user = User.new(1, account_type: "premium", premium: false)
    workflow = NestedBranchWorkflow.new(user, params: { user_id: 1 })

    result = workflow.call

    assert result[:success]
    assert_equal [:validate, :premium_feature, :basic_nested, :finalize], result[:metadata][:steps_executed]
    assert_equal 2, result[:metadata][:branches_taken].count
  end

  test "branch failure triggers rollback" do
    user = User.new(1, premium: true)
    workflow = FailingBranchWorkflow.new(user, params: { user_id: 1 })

    error = assert_raises(BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError) do
      workflow.call
    end

    assert_match(/Workflow execution failed/, error.message)
    assert_equal :workflow_failed, error.code
  end

  test "no matching branch without otherwise raises error" do
    user = User.new(1, account_type: "basic")
    workflow = NoBranchMatchWorkflow.new(user, params: { user_id: 1 })

    error = assert_raises(BetterService::Errors::Configuration::InvalidConfigurationError) do
      workflow.call
    end

    assert_match(/No matching branch found/, error.message)
    assert_equal :configuration_error, error.code
  end

  test "branch metadata includes all branch decisions" do
    user = User.new(1, account_type: "premium", premium: true)
    workflow = NestedBranchWorkflow.new(user, params: { user_id: 1 })

    result = workflow.call

    assert result[:metadata].key?(:branches_taken)
    assert_kind_of Array, result[:metadata][:branches_taken]
    assert result[:metadata][:branches_taken].all? { |b| b.is_a?(String) }
  end

  test "workflow without branches does not have branches_taken metadata" do
    class SimpleWorkflow < BetterService::Workflows::Base
      step :validate,
           with: ValidateService,
           input: ->(ctx) { { user_id: ctx.user_id } }
    end

    user = User.new(1)
    workflow = SimpleWorkflow.new(user, params: { user_id: 1 })

    result = workflow.call

    assert result[:success]
    refute result[:metadata].key?(:branches_taken)
  end
end
