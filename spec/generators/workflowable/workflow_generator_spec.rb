# frozen_string_literal: true

require "rails_helper"
require "generators/workflowable/workflow_generator"

RSpec.describe Workflowable::Generators::WorkflowGenerator, type: :generator do
  tests Workflowable::Generators::WorkflowGenerator

  describe "basic generation" do
    it "generates workflow file in correct location" do
      run_generator [ "order/purchase" ]

      assert_file "app/workflows/order/purchase_workflow.rb"
    end

    it "generates workflow with correct class name" do
      run_generator [ "order/purchase" ]

      assert_file "app/workflows/order/purchase_workflow.rb" do |content|
        expect(content).to match(/class Order::PurchaseWorkflow/)
      end
    end

    it "generates workflow inheriting from BetterService::Workflow" do
      run_generator [ "order/purchase" ]

      assert_file "app/workflows/order/purchase_workflow.rb" do |content|
        expect(content).to match(/< BetterService::Workflow/)
      end
    end

    it "generates test file by default" do
      run_generator [ "order/purchase" ]

      assert_file "test/workflows/order/purchase_workflow_test.rb" do |content|
        expect(content).to match(/class Order::PurchaseWorkflowTest < ActiveSupport::TestCase/)
      end
    end
  end

  describe "step generation" do
    it "generates workflow with steps when provided" do
      run_generator [ "order/purchase", "--steps", "create_order", "charge_payment", "send_email" ]

      assert_file "app/workflows/order/purchase_workflow.rb" do |content|
        expect(content).to match(/step :create_order/)
        expect(content).to match(/step :charge_payment/)
        expect(content).to match(/step :send_email/)
      end
    end

    it "generates steps with correct service class names" do
      run_generator [ "order/purchase", "--steps", "create_order" ]

      assert_file "app/workflows/order/purchase_workflow.rb" do |content|
        expect(content).to match(/with: Order::Purchase::CreateOrderService/)
      end
    end

    it "generates workflow without steps by default" do
      run_generator [ "order/purchase" ]

      assert_file "app/workflows/order/purchase_workflow.rb" do |content|
        expect(content).to match(/# Example step configuration:/)
      end
    end
  end

  describe "transaction option" do
    it "generates workflow with transaction when option provided" do
      run_generator [ "order/purchase", "--transaction" ]

      assert_file "app/workflows/order/purchase_workflow.rb" do |content|
        expect(content).to match(/with_transaction true/)
      end
    end

    it "generates workflow without transaction by default" do
      run_generator [ "order/purchase" ]

      assert_file "app/workflows/order/purchase_workflow.rb" do |content|
        expect(content).to match(/# Database transactions are DISABLED by default/)
      end
    end
  end

  describe "skip test option" do
    it "skips test file when --skip_test option provided" do
      run_generator [ "order/purchase", "--skip_test" ]

      assert_file "app/workflows/order/purchase_workflow.rb"
      assert_no_file "test/workflows/order/purchase_workflow_test.rb"
    end
  end

  describe "namespace handling" do
    it "generates workflow in namespace directory" do
      run_generator [ "admin/order/purchase" ]

      assert_file "app/workflows/admin/order/purchase_workflow.rb" do |content|
        expect(content).to match(/class Admin::Order::PurchaseWorkflow/)
      end
    end

    it "generates test in namespace directory" do
      run_generator [ "admin/order/purchase" ]

      assert_file "test/workflows/admin/order/purchase_workflow_test.rb" do |content|
        expect(content).to match(/class Admin::Order::PurchaseWorkflowTest/)
      end
    end
  end

  describe "test file content" do
    it "generates test file with workflow execution test" do
      run_generator [ "order/purchase" ]

      assert_file "test/workflows/order/purchase_workflow_test.rb" do |content|
        expect(content).to match(/test "workflow executes successfully with valid params"/)
      end
    end

    it "generates test file with workflow failure test" do
      run_generator [ "order/purchase" ]

      assert_file "test/workflows/order/purchase_workflow_test.rb" do |content|
        expect(content).to match(/test "workflow fails with invalid params"/)
      end
    end

    it "generates test file with steps tracking test" do
      run_generator [ "order/purchase" ]

      assert_file "test/workflows/order/purchase_workflow_test.rb" do |content|
        expect(content).to match(/test "workflow tracks executed steps"/)
      end
    end

    it "generates test with transaction rollback test when transaction enabled" do
      run_generator [ "order/purchase", "--transaction" ]

      assert_file "test/workflows/order/purchase_workflow_test.rb" do |content|
        expect(content).to match(/test "workflow rolls back database changes on failure"/)
      end
    end
  end

  describe "simple name handling" do
    it "generates simple workflow without namespace" do
      run_generator [ "purchase" ]

      assert_file "app/workflows/purchase_workflow.rb" do |content|
        expect(content).to match(/class PurchaseWorkflow/)
      end
    end

    it "generates test for simple workflow without namespace" do
      run_generator [ "purchase" ]

      assert_file "test/workflows/purchase_workflow_test.rb" do |content|
        expect(content).to match(/class PurchaseWorkflowTest/)
      end
    end
  end
end
