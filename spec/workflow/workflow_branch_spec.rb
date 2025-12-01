# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workflow Branch", type: :workflow do
  class WorkflowBranchTestUser
    attr_accessor :id, :account_type, :premium

    def initialize(id, account_type: "basic", premium: false)
      @id = id
      @account_type = account_type
      @premium = premium
    end
  end

  # Mock services for testing
  class WBValidateService < BetterService::Services::Base
    schema do
      required(:user_id).filled(:integer)
    end

    process_with do |data|
      { resource: { user_id: params[:user_id], validated: true } }
    end
  end

  class WBPremiumService < BetterService::Services::Base
    schema { optional(:context).filled }

    process_with do |data|
      { resource: { feature: "premium", executed: true } }
    end
  end

  class WBBasicService < BetterService::Services::Base
    schema { optional(:context).filled }

    process_with do |data|
      { resource: { feature: "basic", executed: true } }
    end
  end

  class WBEnterpriseService < BetterService::Services::Base
    schema { optional(:context).filled }

    process_with do |data|
      { resource: { feature: "enterprise", executed: true } }
    end
  end

  class WBDefaultService < BetterService::Services::Base
    schema { optional(:context).filled }

    process_with do |data|
      { resource: { feature: "default", executed: true } }
    end
  end

  class WBFailingService < BetterService::Services::Base
    schema { optional(:context).filled }

    process_with do |data|
      raise StandardError, "Service failed"
    end
  end

  class WBFinalService < BetterService::Services::Base
    schema { optional(:context).filled }

    process_with do |data|
      { resource: { final: true } }
    end
  end

  # Test workflows
  class SimpleBranchWorkflow < BetterService::Workflows::Base
    step :validate,
         with: WBValidateService,
         input: ->(ctx) { { user_id: ctx.user_id } }

    branch do
      on ->(ctx) { ctx.user.premium } do
        step :premium_feature, with: WBPremiumService
      end

      otherwise do
        step :basic_feature, with: WBBasicService
      end
    end

    step :finalize, with: WBFinalService
  end

  class MultiBranchWorkflow < BetterService::Workflows::Base
    step :validate,
         with: WBValidateService,
         input: ->(ctx) { { user_id: ctx.user_id } }

    branch do
      on ->(ctx) { ctx.user.account_type == "enterprise" } do
        step :enterprise_feature, with: WBEnterpriseService
      end

      on ->(ctx) { ctx.user.account_type == "premium" } do
        step :premium_feature, with: WBPremiumService
      end

      on ->(ctx) { ctx.user.account_type == "basic" } do
        step :basic_feature, with: WBBasicService
      end

      otherwise do
        step :default_feature, with: WBDefaultService
      end
    end

    step :finalize, with: WBFinalService
  end

  class NestedBranchWorkflow < BetterService::Workflows::Base
    step :validate,
         with: WBValidateService,
         input: ->(ctx) { { user_id: ctx.user_id } }

    branch do
      on ->(ctx) { ctx.user.account_type == "premium" } do
        step :premium_feature, with: WBPremiumService

        branch do
          on ->(ctx) { ctx.user.premium } do
            step :premium_nested, with: WBPremiumService
          end

          otherwise do
            step :basic_nested, with: WBBasicService
          end
        end
      end

      otherwise do
        step :basic_feature, with: WBBasicService
      end
    end

    step :finalize, with: WBFinalService
  end

  class FailingBranchWorkflow < BetterService::Workflows::Base
    step :validate,
         with: WBValidateService,
         input: ->(ctx) { { user_id: ctx.user_id } }

    branch do
      on ->(ctx) { ctx.user.premium } do
        step :failing_step, with: WBFailingService
      end

      otherwise do
        step :basic_feature, with: WBBasicService
      end
    end

    step :finalize, with: WBFinalService
  end

  class NoBranchMatchWorkflow < BetterService::Workflows::Base
    step :validate,
         with: WBValidateService,
         input: ->(ctx) { { user_id: ctx.user_id } }

    branch do
      on ->(ctx) { ctx.user.account_type == "nonexistent" } do
        step :premium_feature, with: WBPremiumService
      end
    end

    step :finalize, with: WBFinalService
  end

  describe SimpleBranchWorkflow do
    context "when condition is true" do
      it "takes first path" do
        user = WorkflowBranchTestUser.new(1, premium: true)
        workflow = SimpleBranchWorkflow.new(user, params: { user_id: 1 })

        result = workflow.call

        expect(result[:success]).to be true
        expect(result[:metadata][:steps_executed]).to eq([ :validate, :premium_feature, :finalize ])
        expect(result[:metadata][:branches_taken]).to include("branch_1:on_1")
        expect(result[:context].premium_feature[:feature]).to eq("premium")
      end
    end

    context "when condition is false" do
      it "takes otherwise path" do
        user = WorkflowBranchTestUser.new(1, premium: false)
        workflow = SimpleBranchWorkflow.new(user, params: { user_id: 1 })

        result = workflow.call

        expect(result[:success]).to be true
        expect(result[:metadata][:steps_executed]).to eq([ :validate, :basic_feature, :finalize ])
        expect(result[:metadata][:branches_taken]).to include("branch_1:otherwise")
        expect(result[:context].basic_feature[:feature]).to eq("basic")
      end
    end
  end

  describe MultiBranchWorkflow do
    it "takes first matching path for enterprise" do
      user = WorkflowBranchTestUser.new(1, account_type: "enterprise")
      workflow = MultiBranchWorkflow.new(user, params: { user_id: 1 })

      result = workflow.call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to eq([ :validate, :enterprise_feature, :finalize ])
      expect(result[:metadata][:branches_taken]).to include("branch_1:on_1")
      expect(result[:context].enterprise_feature[:feature]).to eq("enterprise")
    end

    it "takes second matching path for premium" do
      user = WorkflowBranchTestUser.new(1, account_type: "premium")
      workflow = MultiBranchWorkflow.new(user, params: { user_id: 1 })

      result = workflow.call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to eq([ :validate, :premium_feature, :finalize ])
      expect(result[:metadata][:branches_taken]).to include("branch_1:on_2")
      expect(result[:context].premium_feature[:feature]).to eq("premium")
    end

    it "takes third matching path for basic" do
      user = WorkflowBranchTestUser.new(1, account_type: "basic")
      workflow = MultiBranchWorkflow.new(user, params: { user_id: 1 })

      result = workflow.call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to eq([ :validate, :basic_feature, :finalize ])
      expect(result[:metadata][:branches_taken]).to include("branch_1:on_3")
      expect(result[:context].basic_feature[:feature]).to eq("basic")
    end

    it "takes otherwise path when no condition matches" do
      user = WorkflowBranchTestUser.new(1, account_type: "unknown")
      workflow = MultiBranchWorkflow.new(user, params: { user_id: 1 })

      result = workflow.call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to eq([ :validate, :default_feature, :finalize ])
      expect(result[:metadata][:branches_taken]).to include("branch_1:otherwise")
      expect(result[:context].default_feature[:feature]).to eq("default")
    end
  end

  describe NestedBranchWorkflow do
    it "works correctly with nested branches" do
      user = WorkflowBranchTestUser.new(1, account_type: "premium", premium: true)
      workflow = NestedBranchWorkflow.new(user, params: { user_id: 1 })

      result = workflow.call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to eq([ :validate, :premium_feature, :premium_nested, :finalize ])
      expect(result[:metadata][:branches_taken].count).to eq(2)
      expect(result[:metadata][:branches_taken]).to include("branch_1:on_1")
    end

    it "takes otherwise in nested level" do
      user = WorkflowBranchTestUser.new(1, account_type: "premium", premium: false)
      workflow = NestedBranchWorkflow.new(user, params: { user_id: 1 })

      result = workflow.call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to eq([ :validate, :premium_feature, :basic_nested, :finalize ])
      expect(result[:metadata][:branches_taken].count).to eq(2)
    end
  end

  describe FailingBranchWorkflow do
    it "triggers rollback on failure" do
      user = WorkflowBranchTestUser.new(1, premium: true)
      workflow = FailingBranchWorkflow.new(user, params: { user_id: 1 })

      expect {
        workflow.call
      }.to raise_error(BetterService::Errors::Workflowable::Runtime::StepExecutionError) do |error|
        expect(error.message).to match(/failing_step failed/)
        expect(error.code).to eq(:step_failed)
      end
    end
  end

  describe NoBranchMatchWorkflow do
    it "raises error without otherwise" do
      user = WorkflowBranchTestUser.new(1, account_type: "basic")
      workflow = NoBranchMatchWorkflow.new(user, params: { user_id: 1 })

      expect {
        workflow.call
      }.to raise_error(BetterService::Errors::Configuration::InvalidConfigurationError) do |error|
        expect(error.message).to match(/No matching branch found/)
        expect(error.code).to eq(:configuration_error)
      end
    end
  end

  describe "branch metadata" do
    it "includes all branch decisions" do
      user = WorkflowBranchTestUser.new(1, account_type: "premium", premium: true)
      workflow = NestedBranchWorkflow.new(user, params: { user_id: 1 })

      result = workflow.call

      expect(result[:metadata]).to have_key(:branches_taken)
      expect(result[:metadata][:branches_taken]).to be_instance_of(Array)
      expect(result[:metadata][:branches_taken].all? { |b| b.is_a?(String) }).to be true
    end
  end

  describe "workflow without branches" do
    it "does not have branches_taken metadata" do
      simple_workflow_class = Class.new(BetterService::Workflows::Base) do
        step :validate,
             with: WBValidateService,
             input: ->(ctx) { { user_id: ctx.user_id } }
      end

      user = WorkflowBranchTestUser.new(1)
      workflow = simple_workflow_class.new(user, params: { user_id: 1 })

      result = workflow.call

      expect(result[:success]).to be true
      expect(result[:metadata]).not_to have_key(:branches_taken)
    end
  end
end
