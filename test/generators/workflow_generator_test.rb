# frozen_string_literal: true

require "test_helper"
require "generators/workflowable/workflow_generator"

class WorkflowGeneratorTest < Rails::Generators::TestCase
  tests Workflowable::Generators::WorkflowGenerator
  destination File.expand_path("../tmp", __dir__)
  setup :prepare_destination

  # ========================================
  # Basic Generation Tests
  # ========================================

  test "generates workflow file in correct location" do
    run_generator ["order/purchase"]

    assert_file "app/workflows/order/purchase_workflow.rb"
  end

  test "generates workflow with correct class name" do
    run_generator ["order/purchase"]

    assert_file "app/workflows/order/purchase_workflow.rb" do |content|
      assert_match(/class Order::PurchaseWorkflow/, content)
    end
  end

  test "generates workflow inheriting from BetterService::Workflow" do
    run_generator ["order/purchase"]

    assert_file "app/workflows/order/purchase_workflow.rb" do |content|
      assert_match(/< BetterService::Workflow/, content)
    end
  end

  test "generates test file by default" do
    run_generator ["order/purchase"]

    assert_file "test/workflows/order/purchase_workflow_test.rb" do |content|
      assert_match(/class Order::PurchaseWorkflowTest < ActiveSupport::TestCase/, content)
    end
  end

  # ========================================
  # Step Generation Tests
  # ========================================

  test "generates workflow with steps when provided" do
    run_generator ["order/purchase", "--steps", "create_order", "charge_payment", "send_email"]

    assert_file "app/workflows/order/purchase_workflow.rb" do |content|
      assert_match(/step :create_order/, content)
      assert_match(/step :charge_payment/, content)
      assert_match(/step :send_email/, content)
    end
  end

  test "generates steps with correct service class names" do
    run_generator ["order/purchase", "--steps", "create_order"]

    assert_file "app/workflows/order/purchase_workflow.rb" do |content|
      assert_match(/with: Order::Purchase::CreateOrderService/, content)
    end
  end

  test "generates workflow without steps by default" do
    run_generator ["order/purchase"]

    assert_file "app/workflows/order/purchase_workflow.rb" do |content|
      # Should have example steps commented out
      assert_match(/# Example step configuration:/, content)
    end
  end

  # ========================================
  # Transaction Option Tests
  # ========================================

  test "generates workflow with transaction when option provided" do
    run_generator ["order/purchase", "--transaction"]

    assert_file "app/workflows/order/purchase_workflow.rb" do |content|
      assert_match(/with_transaction true/, content)
    end
  end

  test "generates workflow without transaction by default" do
    run_generator ["order/purchase"]

    assert_file "app/workflows/order/purchase_workflow.rb" do |content|
      assert_match(/# Database transactions are DISABLED by default/, content)
    end
  end

  # ========================================
  # Skip Test Option Tests
  # ========================================

  test "skips test file when --skip_test option provided" do
    run_generator ["order/purchase", "--skip_test"]

    assert_file "app/workflows/order/purchase_workflow.rb"
    assert_no_file "test/workflows/order/purchase_workflow_test.rb"
  end

  # ========================================
  # Namespace Tests
  # ========================================

  test "generates workflow in namespace directory" do
    run_generator ["admin/order/purchase"]

    assert_file "app/workflows/admin/order/purchase_workflow.rb" do |content|
      assert_match(/class Admin::Order::PurchaseWorkflow/, content)
    end
  end

  test "generates test in namespace directory" do
    run_generator ["admin/order/purchase"]

    assert_file "test/workflows/admin/order/purchase_workflow_test.rb" do |content|
      assert_match(/class Admin::Order::PurchaseWorkflowTest/, content)
    end
  end

  # ========================================
  # Test File Content Tests
  # ========================================

  test "generates test file with workflow execution test" do
    run_generator ["order/purchase"]

    assert_file "test/workflows/order/purchase_workflow_test.rb" do |content|
      assert_match(/test "workflow executes successfully with valid params"/, content)
    end
  end

  test "generates test file with workflow failure test" do
    run_generator ["order/purchase"]

    assert_file "test/workflows/order/purchase_workflow_test.rb" do |content|
      assert_match(/test "workflow fails with invalid params"/, content)
    end
  end

  test "generates test file with steps tracking test" do
    run_generator ["order/purchase"]

    assert_file "test/workflows/order/purchase_workflow_test.rb" do |content|
      assert_match(/test "workflow tracks executed steps"/, content)
    end
  end

  test "generates test with transaction rollback test when transaction enabled" do
    run_generator ["order/purchase", "--transaction"]

    assert_file "test/workflows/order/purchase_workflow_test.rb" do |content|
      assert_match(/test "workflow rolls back database changes on failure"/, content)
    end
  end

  # ========================================
  # Simple Name Tests
  # ========================================

  test "generates simple workflow without namespace" do
    run_generator ["purchase"]

    assert_file "app/workflows/purchase_workflow.rb" do |content|
      assert_match(/class PurchaseWorkflow/, content)
    end
  end

  test "generates test for simple workflow without namespace" do
    run_generator ["purchase"]

    assert_file "test/workflows/purchase_workflow_test.rb" do |content|
      assert_match(/class PurchaseWorkflowTest/, content)
    end
  end
end
