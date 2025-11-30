# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Concurrent Workflow Scenarios" do
  # Test user class
  class ConcurrentWorkflowTestUser
    attr_accessor :id, :name

    def initialize(id, name: "Test User")
      @id = id
      @name = name
    end
  end

  # Mock services
  class ConcurrentWorkflowMockService < BetterService::Services::Base
    schema do
      optional(:value).maybe(:integer)
      optional(:label).maybe(:string)
    end

    process_with do |_data|
      { resource: { processed: true, value: params[:value], label: params[:label], timestamp: Time.current.to_f } }
    end
  end

  class ConcurrentWorkflowDelayedService < BetterService::Services::Base
    schema do
      optional(:delay_ms).maybe(:integer)
    end

    process_with do |_data|
      delay = (params[:delay_ms] || 10) / 1000.0
      sleep(delay)
      { resource: { completed: true, delay: delay } }
    end
  end

  let(:user) { ConcurrentWorkflowTestUser.new(1) }

  describe "Multiple workflows with same context structure" do
    class WorkflowA < BetterService::Workflows::Base
      step :process_a, with: ConcurrentWorkflowMockService, input: ->(ctx) { { label: "workflow_a" } }
    end

    class WorkflowB < BetterService::Workflows::Base
      step :process_b, with: ConcurrentWorkflowMockService, input: ->(ctx) { { label: "workflow_b" } }
    end

    it "can run multiple different workflows sequentially with same user" do
      result_a = WorkflowA.new(user, params: {}).call
      result_b = WorkflowB.new(user, params: {}).call

      expect(result_a[:success]).to be true
      expect(result_b[:success]).to be true
      expect(result_a[:context].process_a[:label]).to eq("workflow_a")
      expect(result_b[:context].process_b[:label]).to eq("workflow_b")
    end

    it "workflows do not share context state" do
      workflow_a = WorkflowA.new(user, params: {})
      workflow_b = WorkflowB.new(user, params: {})

      result_a = workflow_a.call
      result_b = workflow_b.call

      # Each workflow has its own context
      expect(result_a[:context]).not_to eq(result_b[:context])
      expect(result_a[:context].respond_to?(:process_b)).to be false
      expect(result_b[:context].respond_to?(:process_a)).to be false
    end
  end

  describe "Workflow state isolation" do
    class StatefulWorkflow < BetterService::Workflows::Base
      step :increment, with: ConcurrentWorkflowMockService, input: ->(ctx) { { value: 10 } }
      step :double, with: ConcurrentWorkflowMockService, input: ->(ctx) { { value: (ctx.increment[:value] || 0) * 2 } }
    end

    it "each workflow instance maintains independent state" do
      workflow1 = StatefulWorkflow.new(user, params: {})
      workflow2 = StatefulWorkflow.new(user, params: {})

      result1 = workflow1.call
      result2 = workflow2.call

      # Both should have same results since they start fresh
      expect(result1[:context].increment[:value]).to eq(result2[:context].increment[:value])
      expect(result1[:context].double[:value]).to eq(result2[:context].double[:value])
    end

    it "running same workflow twice produces independent results" do
      results = 2.times.map do
        StatefulWorkflow.new(user, params: {}).call
      end

      expect(results[0][:context].object_id).not_to eq(results[1][:context].object_id)
    end
  end

  describe "Context collision prevention" do
    class ContextWriteWorkflow < BetterService::Workflows::Base
      step :write_data, with: ConcurrentWorkflowMockService, input: ->(ctx) { { label: "data_#{ctx.user.id}" } }
      step :verify_data, with: ConcurrentWorkflowMockService, input: ->(ctx) { { label: ctx.write_data[:label] } }
    end

    it "context data from one workflow does not leak to another" do
      user1 = ConcurrentWorkflowTestUser.new(100)
      user2 = ConcurrentWorkflowTestUser.new(200)

      result1 = ContextWriteWorkflow.new(user1, params: {}).call
      result2 = ContextWriteWorkflow.new(user2, params: {}).call

      expect(result1[:context].write_data[:label]).to eq("data_100")
      expect(result2[:context].write_data[:label]).to eq("data_200")
      expect(result1[:context].write_data[:label]).not_to eq(result2[:context].write_data[:label])
    end

    it "simultaneous workflow executions maintain isolation" do
      users = 5.times.map { |i| ConcurrentWorkflowTestUser.new(i) }

      results = users.map do |u|
        ContextWriteWorkflow.new(u, params: {}).call
      end

      results.each_with_index do |result, index|
        expect(result[:context].write_data[:label]).to eq("data_#{index}")
      end
    end
  end

  describe "Step name uniqueness validation" do
    it "allows same step names in different workflows" do
      workflow_class_1 = Class.new(BetterService::Workflows::Base) do
        step :process, with: ConcurrentWorkflowMockService, input: ->(ctx) { { label: "first" } }
      end

      workflow_class_2 = Class.new(BetterService::Workflows::Base) do
        step :process, with: ConcurrentWorkflowMockService, input: ->(ctx) { { label: "second" } }
      end

      result1 = workflow_class_1.new(user, params: {}).call
      result2 = workflow_class_2.new(user, params: {}).call

      expect(result1[:success]).to be true
      expect(result2[:success]).to be true
      expect(result1[:context].process[:label]).to eq("first")
      expect(result2[:context].process[:label]).to eq("second")
    end

    it "step results are stored under step name in context" do
      workflow_class = Class.new(BetterService::Workflows::Base) do
        step :step_alpha, with: ConcurrentWorkflowMockService, input: ->(ctx) { { label: "alpha" } }
        step :step_beta, with: ConcurrentWorkflowMockService, input: ->(ctx) { { label: "beta" } }
        step :step_gamma, with: ConcurrentWorkflowMockService, input: ->(ctx) { { label: "gamma" } }
      end

      result = workflow_class.new(user, params: {}).call

      expect(result[:context].step_alpha).to be_present
      expect(result[:context].step_beta).to be_present
      expect(result[:context].step_gamma).to be_present
    end
  end

  describe "Workflow composition patterns" do
    class InnerWorkflowService < BetterService::Services::Base
      schema do
        optional(:input_value).maybe(:integer)
      end

      process_with do |_data|
        { resource: { result: (params[:input_value] || 0) * 2 } }
      end
    end

    class ComposedWorkflow < BetterService::Workflows::Base
      step :prepare, with: ConcurrentWorkflowMockService, input: ->(ctx) { { value: 10 } }
      step :transform, with: InnerWorkflowService, input: ->(ctx) { { input_value: ctx.prepare[:value] } }
      step :finalize, with: ConcurrentWorkflowMockService, input: ->(ctx) { { value: ctx.transform[:result] } }
    end

    it "can compose workflows that pass data through steps" do
      result = ComposedWorkflow.new(user, params: {}).call

      expect(result[:success]).to be true
      expect(result[:context].prepare[:value]).to eq(10)
      expect(result[:context].transform[:result]).to eq(20)  # 10 * 2
      expect(result[:context].finalize[:value]).to eq(20)
    end

    it "maintains data flow integrity through composition" do
      result = ComposedWorkflow.new(user, params: {}).call

      # Verify the data flow chain
      initial_value = result[:context].prepare[:value]
      transformed_value = result[:context].transform[:result]
      final_value = result[:context].finalize[:value]

      expect(transformed_value).to eq(initial_value * 2)
      expect(final_value).to eq(transformed_value)
    end
  end
end
