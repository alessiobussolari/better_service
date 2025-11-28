# frozen_string_literal: true

# Manual Test Script for BetterService Workflow Branching
#
# This script runs comprehensive manual tests with real database models
# to verify workflow branching functionality works correctly end-to-end.
#
# Usage:
#   cd test/dummy
#   rails console
#   load '../../manual_test.rb'
#
# All tests run inside database transactions that are automatically rolled back,
# so no data persists after the tests complete.

# Color output helpers
class String
  def colorize(color_code)
    "\e[#{color_code}m#{self}\e[0m"
  end

  def red;    colorize(31) end
  def green;  colorize(32) end
  def yellow; colorize(33) end
  def blue;   colorize(34) end
  def bold;   colorize(1)  end
end

class WorkflowBranchingManualTest
  attr_reader :results

  def initialize
    @results = []
    @start_time = Time.current
  end

  def run_all
    puts "\n" + ("=" * 80).blue
    puts "  BetterService Workflow Branching - Manual Test Suite".bold.blue
    puts ("=" * 80).blue + "\n\n"

    # Run all test scenarios
    test_ecommerce_order_processing
    test_content_approval_workflow
    test_subscription_renewal_workflow

    # Print summary
    print_summary
  end

  private

  # Test Scenario 1: E-commerce Order Processing with Payment Branch
  def test_ecommerce_order_processing
    test_name = "E-commerce Order Processing (Payment Method Branching)"
    puts "\n#{test_name}".bold
    puts "-" * test_name.length

    ActiveRecord::Base.transaction do
      # Setup
      user = User.create!(name: "John Doe", email: "john@example.com")

      # Test 1: Credit Card Payment
      puts "\n  Test 1.1: Credit Card Payment Path".yellow
      result1 = run_test do
        # Define mock services OUTSIDE the workflow class
        validate_service = create_service("ValidateOrder") do
          { resource: { order_id: 1, payment_method: "credit_card", total: 99.99 } }
        end

        charge_card_service = create_service("ChargeCreditCard") do
          { resource: { charge_id: "ch_123", status: "succeeded" } }
        end

        verify_3ds_service = create_service("Verify3DSecure") do
          { resource: { verified: true } }
        end

        charge_paypal_service = create_service("ChargePaypal") do
          { resource: {} }
        end

        manual_payment_service = create_service("ManualPayment") do
          { resource: {} }
        end

        finalize_service = create_service("FinalizeOrder") do
          { resource: { order: { id: 1, status: "completed" } } }
        end

        # Define workflow - capture services in local variables for closure
        vs = validate_service
        ccs = charge_card_service
        v3ds = verify_3ds_service
        cps = charge_paypal_service
        mps = manual_payment_service
        fs = finalize_service

        workflow_class = Class.new(BetterService::Workflows::Base) do
          step :validate, with: vs

          branch do
            on ->(ctx) { ctx.validate[:payment_method] == "credit_card" } do
              step :charge_card, with: ccs
              step :verify_3ds, with: v3ds, optional: true
            end

            on ->(ctx) { ctx.validate[:payment_method] == "paypal" } do
              step :charge_paypal, with: cps
            end

            otherwise do
              step :manual_payment, with: mps
            end
          end

          step :finalize, with: fs
        end

        result = workflow_class.new(user, params: {}).call

        assert result[:success], "Workflow should succeed"
        assert_equal [:validate, :charge_card, :verify_3ds, :finalize], result[:metadata][:steps_executed]
        assert_includes result[:metadata][:branches_taken], "branch_1:on_1"

        result
      end

      print_test_result("Credit Card Path", result1)

      # Test 2: PayPal Payment
      puts "\n  Test 1.2: PayPal Payment Path".yellow
      result2 = run_test do
        validate_service = create_service("ValidateOrder") do
          { resource: { order_id: 2, payment_method: "paypal", total: 149.99 } }
        end

        charge_card_service = create_service("ChargeCard") do
          { resource: {} }
        end

        charge_paypal_service = create_service("ChargePaypal") do
          { resource: { paypal_id: "PAY-123", status: "approved" } }
        end

        manual_payment_service = create_service("ManualPayment") do
          { resource: {} }
        end

        finalize_service = create_service("FinalizeOrder") do
          { resource: { order: { id: 2, status: "completed" } } }
        end

        vs = validate_service
        ccs = charge_card_service
        cps = charge_paypal_service
        mps = manual_payment_service
        fs = finalize_service

        workflow_class = Class.new(BetterService::Workflows::Base) do
          step :validate, with: vs

          branch do
            on ->(ctx) { ctx.validate[:payment_method] == "credit_card" } do
              step :charge_card, with: ccs
            end

            on ->(ctx) { ctx.validate[:payment_method] == "paypal" } do
              step :charge_paypal, with: cps
            end

            otherwise do
              step :manual_payment, with: mps
            end
          end

          step :finalize, with: fs
        end

        result = workflow_class.new(user, params: {}).call

        assert result[:success], "Workflow should succeed"
        assert_equal [:validate, :charge_paypal, :finalize], result[:metadata][:steps_executed]
        assert_includes result[:metadata][:branches_taken], "branch_1:on_2"

        result
      end

      print_test_result("PayPal Path", result2)

      # Test 3: Default Payment Path
      puts "\n  Test 1.3: Bank Transfer (Otherwise) Path".yellow
      result3 = run_test do
        validate_service = create_service("ValidateOrder") do
          { resource: { order_id: 3, payment_method: "bank_transfer", total: 299.99 } }
        end

        charge_card_service = create_service("ChargeCard") do
          { resource: {} }
        end

        charge_paypal_service = create_service("ChargePaypal") do
          { resource: {} }
        end

        manual_payment_service = create_service("ManualPayment") do
          { resource: { reference: "REF-123", instructions: "sent" } }
        end

        finalize_service = create_service("FinalizeOrder") do
          { resource: { order: { id: 3, status: "pending" } } }
        end

        vs = validate_service
        ccs = charge_card_service
        cps = charge_paypal_service
        mps = manual_payment_service
        fs = finalize_service

        workflow_class = Class.new(BetterService::Workflows::Base) do
          step :validate, with: vs

          branch do
            on ->(ctx) { ctx.validate[:payment_method] == "credit_card" } do
              step :charge_card, with: ccs
            end

            on ->(ctx) { ctx.validate[:payment_method] == "paypal" } do
              step :charge_paypal, with: cps
            end

            otherwise do
              step :manual_payment, with: mps
            end
          end

          step :finalize, with: fs
        end

        result = workflow_class.new(user, params: {}).call

        assert result[:success], "Workflow should succeed"
        assert_equal [:validate, :manual_payment, :finalize], result[:metadata][:steps_executed]
        assert_includes result[:metadata][:branches_taken], "branch_1:otherwise"

        result
      end

      print_test_result("Bank Transfer (Otherwise) Path", result3)

      raise ActiveRecord::Rollback
    end
  end

  # Test Scenario 2: Content Approval Workflow with Nested Branches
  def test_content_approval_workflow
    test_name = "Content Approval Workflow (Nested Branching)"
    puts "\n\n#{test_name}".bold
    puts "-" * test_name.length

    ActiveRecord::Base.transaction do
      user = User.create!(name: "Admin User", email: "admin@example.com")

      # Test 1: High-value Contract (CEO + Board)
      puts "\n  Test 2.1: High-value Contract Approval".yellow
      result1 = run_test do
        validate_service = create_service("ValidateDocument") do
          { resource: { doc_id: 1, type: "contract", value: 150_000 } }
        end

        legal_review_service = create_service("LegalReview") do
          { resource: { approved: true, reviewed_by: "Legal Team" } }
        end

        ceo_approval_service = create_service("CEOApproval") do
          { resource: { approved: true, approved_by: "CEO" } }
        end

        board_approval_service = create_service("BoardApproval") do
          { resource: { approved: true, approved_by: "Board" } }
        end

        manager_approval_service = create_service("ManagerApproval") do
          { resource: {} }
        end

        supervisor_approval_service = create_service("SupervisorApproval") do
          { resource: {} }
        end

        finance_approval_service = create_service("FinanceApproval") do
          { resource: {} }
        end

        standard_approval_service = create_service("StandardApproval") do
          { resource: {} }
        end

        finalize_service = create_service("FinalizeDocument") do
          { resource: { doc_id: 1, status: "approved" } }
        end

        vs = validate_service
        lrs = legal_review_service
        ceos = ceo_approval_service
        bas = board_approval_service
        mas = manager_approval_service
        sas = supervisor_approval_service
        fas = finance_approval_service
        stas = standard_approval_service
        fs = finalize_service

        workflow_class = Class.new(BetterService::Workflows::Base) do
          step :validate, with: vs

          branch do
            on ->(ctx) { ctx.validate[:type] == "contract" } do
              step :legal_review, with: lrs

              # Nested branch based on contract value
              branch do
                on ->(ctx) { ctx.validate[:value] > 100_000 } do
                  step :ceo_approval, with: ceos
                  step :board_approval, with: bas
                end

                on ->(ctx) { ctx.validate[:value] > 10_000 } do
                  step :manager_approval, with: mas
                end

                otherwise do
                  step :supervisor_approval, with: sas
                end
              end
            end

            on ->(ctx) { ctx.validate[:type] == "invoice" } do
              step :finance_approval, with: fas
            end

            otherwise do
              step :standard_approval, with: stas
            end
          end

          step :finalize, with: fs
        end

        result = workflow_class.new(user, params: {}).call

        assert result[:success], "Workflow should succeed"
        assert_equal [:validate, :legal_review, :ceo_approval, :board_approval, :finalize],
                     result[:metadata][:steps_executed]
        assert_equal 2, result[:metadata][:branches_taken].count, "Should have 2 branch decisions"

        result
      end

      print_test_result("High-value Contract (Nested)", result1)

      # Test 2: Mid-value Contract (Manager only)
      puts "\n  Test 2.2: Mid-value Contract Approval".yellow
      result2 = run_test do
        validate_service = create_service("ValidateDocument") do
          { resource: { doc_id: 2, type: "contract", value: 50_000 } }
        end

        legal_review_service = create_service("LegalReview") do
          { resource: { approved: true } }
        end

        ceo_approval_service = create_service("CEOApproval") do
          { resource: {} }
        end

        manager_approval_service = create_service("ManagerApproval") do
          { resource: { approved: true, approved_by: "Manager" } }
        end

        supervisor_approval_service = create_service("SupervisorApproval") do
          { resource: {} }
        end

        standard_approval_service = create_service("StandardApproval") do
          { resource: {} }
        end

        finalize_service = create_service("FinalizeDocument") do
          { resource: { doc_id: 2, status: "approved" } }
        end

        vs = validate_service
        lrs = legal_review_service
        ceos = ceo_approval_service
        mas = manager_approval_service
        sas = supervisor_approval_service
        stas = standard_approval_service
        fs = finalize_service

        workflow_class = Class.new(BetterService::Workflows::Base) do
          step :validate, with: vs

          branch do
            on ->(ctx) { ctx.validate[:type] == "contract" } do
              step :legal_review, with: lrs

              branch do
                on ->(ctx) { ctx.validate[:value] > 100_000 } do
                  step :ceo_approval, with: ceos
                end

                on ->(ctx) { ctx.validate[:value] > 10_000 } do
                  step :manager_approval, with: mas
                end

                otherwise do
                  step :supervisor_approval, with: sas
                end
              end
            end

            otherwise do
              step :standard_approval, with: stas
            end
          end

          step :finalize, with: fs
        end

        result = workflow_class.new(user, params: {}).call

        assert result[:success], "Workflow should succeed"
        assert_equal [:validate, :legal_review, :manager_approval, :finalize],
                     result[:metadata][:steps_executed]
        assert_equal 2, result[:metadata][:branches_taken].count

        result
      end

      print_test_result("Mid-value Contract (Nested)", result2)

      raise ActiveRecord::Rollback
    end
  end

  # Test Scenario 3: Subscription Renewal Workflow
  def test_subscription_renewal_workflow
    test_name = "Subscription Renewal Workflow (Multi-branch + Complex Conditions)"
    puts "\n\n#{test_name}".bold
    puts "-" * test_name.length

    ActiveRecord::Base.transaction do
      user = User.create!(name: "Subscriber", email: "sub@example.com")

      # Test 1: Enterprise with Custom Billing
      puts "\n  Test 3.1: Enterprise Custom Billing".yellow
      result1 = run_test do
        fetch_sub_service = create_service("FetchSubscription") do
          { resource: { sub_id: 1, plan_tier: "enterprise", custom_billing: true, amount: 10_000 } }
        end

        generate_invoice_service = create_service("GenerateCustomInvoice") do
          { resource: { invoice_id: "INV-001", amount: 10_000 } }
        end

        send_accounting_service = create_service("SendToAccounting") do
          { resource: { sent: true } }
        end

        charge_premium_service = create_service("ChargePremium") do
          { resource: {} }
        end

        charge_basic_service = create_service("ChargeBasic") do
          { resource: {} }
        end

        suspend_service = create_service("Suspend") do
          { resource: {} }
        end

        finalize_service = create_service("LogRenewal") do
          { resource: { renewed: true } }
        end

        fss = fetch_sub_service
        gis = generate_invoice_service
        sas = send_accounting_service
        cps = charge_premium_service
        cbs = charge_basic_service
        sus = suspend_service
        fs = finalize_service

        workflow_class = Class.new(BetterService::Workflows::Base) do
          step :fetch_subscription, with: fss

          branch do
            on ->(ctx) {
              ctx.fetch_subscription[:plan_tier] == "enterprise" &&
              ctx.fetch_subscription[:custom_billing] == true
            } do
              step :generate_invoice, with: gis
              step :send_accounting, with: sas
            end

            on ->(ctx) { ctx.fetch_subscription[:plan_tier] == "premium" } do
              step :charge_premium, with: cps
            end

            on ->(ctx) { ctx.fetch_subscription[:plan_tier] == "basic" } do
              step :charge_basic, with: cbs
            end

            otherwise do
              step :suspend_subscription, with: sus
            end
          end

          step :log_renewal, with: fs
        end

        result = workflow_class.new(user, params: {}).call

        assert result[:success], "Workflow should succeed"
        assert_equal [:fetch_subscription, :generate_invoice, :send_accounting, :log_renewal],
                     result[:metadata][:steps_executed]
        assert_includes result[:metadata][:branches_taken], "branch_1:on_1"

        result
      end

      print_test_result("Enterprise Custom Billing", result1)

      # Test 2: Premium Subscriber
      puts "\n  Test 3.2: Premium Subscription Renewal".yellow
      result2 = run_test do
        fetch_sub_service = create_service("FetchSubscription") do
          { resource: { sub_id: 2, plan_tier: "premium", custom_billing: false, amount: 99 } }
        end

        generate_invoice_service = create_service("GenerateInvoice") do
          { resource: {} }
        end

        charge_premium_service = create_service("ChargePremium") do
          { resource: { charge_id: "ch_premium_123", status: "succeeded" } }
        end

        charge_basic_service = create_service("ChargeBasic") do
          { resource: {} }
        end

        suspend_service = create_service("Suspend") do
          { resource: {} }
        end

        finalize_service = create_service("LogRenewal") do
          { resource: { renewed: true } }
        end

        fss = fetch_sub_service
        gis = generate_invoice_service
        cps = charge_premium_service
        cbs = charge_basic_service
        sus = suspend_service
        fs = finalize_service

        workflow_class = Class.new(BetterService::Workflows::Base) do
          step :fetch_subscription, with: fss

          branch do
            on ->(ctx) {
              ctx.fetch_subscription[:plan_tier] == "enterprise" &&
              ctx.fetch_subscription[:custom_billing] == true
            } do
              step :generate_invoice, with: gis
            end

            on ->(ctx) { ctx.fetch_subscription[:plan_tier] == "premium" } do
              step :charge_premium, with: cps
            end

            on ->(ctx) { ctx.fetch_subscription[:plan_tier] == "basic" } do
              step :charge_basic, with: cbs
            end

            otherwise do
              step :suspend_subscription, with: sus
            end
          end

          step :log_renewal, with: fs
        end

        result = workflow_class.new(user, params: {}).call

        assert result[:success], "Workflow should succeed"
        assert_equal [:fetch_subscription, :charge_premium, :log_renewal],
                     result[:metadata][:steps_executed]
        assert_includes result[:metadata][:branches_taken], "branch_1:on_2"

        result
      end

      print_test_result("Premium Subscription", result2)

      raise ActiveRecord::Rollback
    end
  end

  # Helper methods

  def create_service(name, &block)
    Class.new(BetterService::Services::Base) do
      define_singleton_method(:name) { "Test::#{name}Service" }

      schema do
        optional(:context).filled
      end

      process_with(&block)
    end
  end

  def run_test
    yield
    { success: true }
  rescue StandardError => e
    { success: false, error: e }
  end

  def assert(condition, message = "Assertion failed")
    raise message unless condition
  end

  def assert_equal(expected, actual, message = nil)
    msg = message || "Expected #{expected.inspect}, got #{actual.inspect}"
    raise msg unless expected == actual
  end

  def assert_includes(collection, item, message = nil)
    msg = message || "Expected #{collection.inspect} to include #{item.inspect}"
    raise msg unless collection.include?(item)
  end

  def print_test_result(name, result)
    if result[:success]
      puts "    ✓ #{name}".green
      @results << { name: name, success: true }
    else
      puts "    ✗ #{name}".red
      puts "      Error: #{result[:error].message}".red if result[:error]
      @results << { name: name, success: false, error: result[:error] }
    end
  end

  def print_summary
    duration = Time.current - @start_time
    passed = @results.count { |r| r[:success] }
    failed = @results.count { |r| !r[:success] }

    puts "\n\n" + ("=" * 80).blue
    puts "  Test Summary".bold.blue
    puts ("=" * 80).blue

    puts "\n  Total Tests: #{@results.count}"
    puts "  Passed: #{passed}".green
    puts "  Failed: #{failed}".send(failed.zero? ? :green : :red)
    puts "  Duration: #{duration.round(2)}s"

    if failed.zero?
      puts "\n  All tests passed! ✓".green.bold
    else
      puts "\n  Some tests failed! ✗".red.bold
      puts "\n  Failed tests:"
      @results.select { |r| !r[:success] }.each do |result|
        puts "    - #{result[:name]}".red
        puts "      #{result[:error].message}".red if result[:error]
      end
    end

    puts "\n" + ("=" * 80).blue + "\n\n"
  end
end

# Run the tests
puts "\nStarting BetterService Workflow Branching Manual Tests..."
puts "Note: All tests run in transactions and will be rolled back.\n"

tester = WorkflowBranchingManualTest.new
tester.run_all

puts "Manual tests completed. Database has been rolled back to original state.\n"
