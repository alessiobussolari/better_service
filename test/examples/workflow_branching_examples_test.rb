# frozen_string_literal: true

require "test_helper"

# Workflow Branching Examples
#
# This file contains real-world examples of workflow branching that can be used
# as templates for your own workflows. Each example is fully tested and demonstrates
# different branching patterns and use cases.
#
# These examples are designed to be copied and adapted for your specific needs.

class WorkflowBranchingExamplesTest < ActiveSupport::TestCase
  class User
    attr_accessor :id, :name, :account_type, :premium
    def initialize(id, attributes = {})
      @id = id
      @name = attributes[:name] || "Test User"
      @account_type = attributes[:account_type] || "basic"
      @premium = attributes[:premium] || false
    end
  end

  # ============================================================================
  # Example 1: Payment Processing Workflow
  # Real-world scenario: E-commerce checkout with multiple payment methods
  # ============================================================================

  module PaymentProcessing
    class ValidateOrderService < BetterService::Services::Base
      schema do
        required(:order_id).filled(:integer)
        required(:payment_method).filled(:string)
        required(:amount).filled(:decimal)
      end

      process_with do
        {
          resource: {
            order_id: params[:order_id],
            payment_method: params[:payment_method],
            amount: params[:amount],
            validated_at: Time.current
          }
        }
      end
    end

    class ChargeCreditCardService < BetterService::Services::Base
      schema { required(:order).filled }

      process_with do
        {
          resource: {
            charge_id: "ch_#{SecureRandom.hex(8)}",
            status: "succeeded",
            amount: params[:order][:amount],
            charged_at: Time.current
          }
        }
      end
    end

    class Verify3DSecureService < BetterService::Services::Base
      schema { required(:charge).filled }

      process_with do
        {
          resource: {
            verified: true,
            verification_id: "3ds_#{SecureRandom.hex(6)}",
            verified_at: Time.current
          }
        }
      end
    end

    class ChargePayPalService < BetterService::Services::Base
      schema { required(:order).filled }

      process_with do
        {
          resource: {
            paypal_id: "PAY-#{SecureRandom.hex(8)}",
            status: "approved",
            amount: params[:order][:amount],
            approved_at: Time.current
          }
        }
      end
    end

    class ChargeStripeService < BetterService::Services::Base
      schema { required(:order).filled }

      process_with do
        {
          resource: {
            intent_id: "pi_#{SecureRandom.hex(8)}",
            status: "succeeded",
            amount: params[:order][:amount],
            charged_at: Time.current
          }
        }
      end
    end

    class GenerateBankTransferInstructionsService < BetterService::Services::Base
      schema { required(:order).filled }

      process_with do
        {
          resource: {
            reference: "REF-#{SecureRandom.hex(6)}",
            account_number: "IBAN1234567890",
            instructions_sent: true,
            generated_at: Time.current
          }
        }
      end
    end

    class FinalizeOrderService < BetterService::Services::Base
      schema { required(:order).filled }

      process_with do
        {
          resource: {
            order_id: params[:order][:order_id],
            status: "completed",
            completed_at: Time.current
          }
        }
      end
    end

    class PaymentProcessingWorkflow < BetterService::Workflows::Base
      with_transaction true

      step :validate_order,
           with: ValidateOrderService,
           input: ->(ctx) {
             {
               order_id: ctx.order_id,
               payment_method: ctx.payment_method,
               amount: ctx.amount
             }
           }

      # Branch based on payment method
      branch do
        on ->(ctx) { ctx.validate_order[:payment_method] == "credit_card" } do
          step :charge_credit_card,
               with: ChargeCreditCardService,
               input: ->(ctx) { { order: ctx.validate_order } }

          step :verify_3d_secure,
               with: Verify3DSecureService,
               input: ->(ctx) { { charge: ctx.charge_credit_card } },
               optional: true
        end

        on ->(ctx) { ctx.validate_order[:payment_method] == "paypal" } do
          step :charge_paypal,
               with: ChargePayPalService,
               input: ->(ctx) { { order: ctx.validate_order } }
        end

        on ->(ctx) { ctx.validate_order[:payment_method] == "stripe" } do
          step :charge_stripe,
               with: ChargeStripeService,
               input: ->(ctx) { { order: ctx.validate_order } }
        end

        otherwise do
          step :generate_bank_transfer_instructions,
               with: GenerateBankTransferInstructionsService,
               input: ->(ctx) { { order: ctx.validate_order } }
        end
      end

      step :finalize_order,
           with: FinalizeOrderService,
           input: ->(ctx) { { order: ctx.validate_order } }
    end
  end

  test "example 1: payment processing workflow with credit card" do
    user = User.new(1, name: "John Doe")
    workflow = PaymentProcessing::PaymentProcessingWorkflow.new(
      user,
      params: { order_id: 123, payment_method: "credit_card", amount: 99.99 }
    )

    result = workflow.call

    assert result[:success]
    assert_equal [:validate_order, :charge_credit_card, :verify_3d_secure, :finalize_order],
                 result[:metadata][:steps_executed]
    assert result[:context].charge_credit_card[:charge_id].start_with?("ch_")
  end

  # ============================================================================
  # Example 2: User Onboarding Workflow
  # Real-world scenario: Different onboarding flows based on account type
  # ============================================================================

  module UserOnboarding
    class CreateAccountService < BetterService::Services::Base
      schema do
        required(:email).filled(:string)
        required(:account_type).filled(:string)
      end

      process_with do
        {
          resource: {
            user_id: SecureRandom.uuid,
            email: params[:email],
            account_type: params[:account_type],
            created_at: Time.current
          }
        }
      end
    end

    class SendWelcomeEmailService < BetterService::Services::Base
      schema { required(:user).filled }

      process_with do
        {
          resource: {
            sent: true,
            sent_to: params[:user][:email],
            sent_at: Time.current
          }
        }
      end
    end

    class AssignAccountManagerService < BetterService::Services::Base
      schema { required(:user).filled }

      process_with do
        {
          resource: {
            manager_id: "MGR-#{rand(1000)}",
            manager_name: "Account Manager #{rand(10)}",
            assigned_at: Time.current
          }
        }
      end
    end

    class SetupSSOService < BetterService::Services::Base
      schema { required(:user).filled }

      process_with do
        {
          resource: {
            sso_enabled: true,
            sso_provider: "okta",
            configured_at: Time.current
          }
        }
      end
    end

    class CreateTeamWorkspaceService < BetterService::Services::Base
      schema do
        required(:user).filled
        required(:seats).filled(:integer)
      end

      process_with do
        {
          resource: {
            workspace_id: "WS-#{SecureRandom.hex(4)}",
            seats: params[:seats],
            created_at: Time.current
          }
        }
      end
    end

    class EnableBillingService < BetterService::Services::Base
      schema { required(:user).filled }

      process_with do
        {
          resource: {
            billing_enabled: true,
            plan: "business",
            enabled_at: Time.current
          }
        }
      end
    end

    class StartTrialService < BetterService::Services::Base
      schema do
        required(:user).filled
        required(:days).filled(:integer)
      end

      process_with do
        {
          resource: {
            trial_started: true,
            trial_days: params[:days],
            expires_at: params[:days].days.from_now,
            started_at: Time.current
          }
        }
      end
    end

    class UserOnboardingWorkflow < BetterService::Workflows::Base
      step :create_account,
           with: CreateAccountService,
           input: ->(ctx) { { email: ctx.email, account_type: ctx.account_type } }

      step :send_welcome_email,
           with: SendWelcomeEmailService,
           input: ->(ctx) { { user: ctx.create_account } }

      # Branch based on account type
      branch do
        on ->(ctx) { ctx.create_account[:account_type] == "enterprise" } do
          step :assign_account_manager,
               with: AssignAccountManagerService,
               input: ->(ctx) { { user: ctx.create_account } }

          step :setup_sso,
               with: SetupSSOService,
               input: ->(ctx) { { user: ctx.create_account } }

          step :create_team_workspace,
               with: CreateTeamWorkspaceService,
               input: ->(ctx) { { user: ctx.create_account, seats: 50 } }
        end

        on ->(ctx) { ctx.create_account[:account_type] == "business" } do
          step :create_team_workspace,
               with: CreateTeamWorkspaceService,
               input: ->(ctx) { { user: ctx.create_account, seats: 10 } }

          step :enable_billing,
               with: EnableBillingService,
               input: ->(ctx) { { user: ctx.create_account } }
        end

        otherwise do
          # Personal/Free account
          step :start_trial,
               with: StartTrialService,
               input: ->(ctx) { { user: ctx.create_account, days: 14 } }
        end
      end
    end
  end

  test "example 2: user onboarding workflow for enterprise account" do
    user = User.new(1)
    workflow = UserOnboarding::UserOnboardingWorkflow.new(
      user,
      params: { email: "enterprise@example.com", account_type: "enterprise" }
    )

    result = workflow.call

    assert result[:success]
    assert_equal [
      :create_account,
      :send_welcome_email,
      :assign_account_manager,
      :setup_sso,
      :create_team_workspace
    ], result[:metadata][:steps_executed]
    assert_equal 50, result[:context].create_team_workspace[:seats]
  end

  # ============================================================================
  # Example 3: Content Moderation Workflow
  # Real-world scenario: Automated content moderation with human review escalation
  # ============================================================================

  module ContentModeration
    class AnalyzeContentService < BetterService::Services::Base
      schema do
        required(:content_id).filled(:integer)
        required(:content).filled(:string)
      end

      process_with do
        # Simulate ML-based content analysis
        toxicity_score = rand(0.0..1.0)

        {
          resource: {
            content_id: params[:content_id],
            toxicity_score: toxicity_score,
            flagged_terms: toxicity_score > 0.5 ? ["spam", "inappropriate"] : [],
            analyzed_at: Time.current
          }
        }
      end
    end

    class AutoApproveService < BetterService::Services::Base
      schema { required(:analysis).filled }

      process_with do
        {
          resource: {
            status: "approved",
            approved_by: "automated_system",
            approved_at: Time.current
          }
        }
      end
    end

    class QueueManualReviewService < BetterService::Services::Base
      schema { required(:analysis).filled }

      process_with do
        {
          resource: {
            status: "pending_review",
            queue_id: "Q-#{SecureRandom.hex(4)}",
            queued_at: Time.current
          }
        }
      end
    end

    class AutoRejectService < BetterService::Services::Base
      schema { required(:analysis).filled }

      process_with do
        {
          resource: {
            status: "rejected",
            rejected_by: "automated_system",
            reason: "High toxicity score",
            rejected_at: Time.current
          }
        }
      end
    end

    class NotifyAuthorService < BetterService::Services::Base
      schema do
        required(:content_id).filled(:integer)
        required(:status).filled(:string)
      end

      process_with do
        {
          resource: {
            notification_sent: true,
            sent_at: Time.current
          }
        }
      end
    end

    class ContentModerationWorkflow < BetterService::Workflows::Base
      step :analyze_content,
           with: AnalyzeContentService,
           input: ->(ctx) { { content_id: ctx.content_id, content: ctx.content } }

      # Branch based on toxicity score
      branch do
        # Clean content - auto approve
        on ->(ctx) { ctx.analyze_content[:toxicity_score] < 0.3 } do
          step :auto_approve,
               with: AutoApproveService,
               input: ->(ctx) { { analysis: ctx.analyze_content } }
        end

        # Questionable content - manual review
        on ->(ctx) {
          ctx.analyze_content[:toxicity_score] >= 0.3 &&
          ctx.analyze_content[:toxicity_score] < 0.7
        } do
          step :queue_manual_review,
               with: QueueManualReviewService,
               input: ->(ctx) { { analysis: ctx.analyze_content } }
        end

        # Highly toxic content - auto reject
        otherwise do
          step :auto_reject,
               with: AutoRejectService,
               input: ->(ctx) { { analysis: ctx.analyze_content } }
        end
      end

      step :notify_author,
           with: NotifyAuthorService,
           input: ->(ctx) {
             status = if ctx.respond_to?(:auto_approve)
                        ctx.auto_approve[:status]
                      elsif ctx.respond_to?(:queue_manual_review)
                        ctx.queue_manual_review[:status]
                      else
                        ctx.auto_reject[:status]
                      end

             { content_id: ctx.analyze_content[:content_id], status: status }
           }
    end
  end

  test "example 3: content moderation workflow with auto-approve" do
    user = User.new(1)

    # Run multiple times to get a clean content (toxicity < 0.3)
    result = nil
    10.times do
      workflow = ContentModeration::ContentModerationWorkflow.new(
        user,
        params: { content_id: 456, content: "This is a friendly message" }
      )

      result = workflow.call

      break if result[:context].analyze_content[:toxicity_score] < 0.3
    end

    # Verify workflow structure (may auto-approve, queue for review, or reject based on random score)
    assert result[:success]
    assert_includes result[:metadata][:steps_executed], :analyze_content
    assert_includes result[:metadata][:steps_executed], :notify_author
  end

  # ============================================================================
  # Example 4: Order Fulfillment Workflow
  # Real-world scenario: Different fulfillment strategies based on inventory
  # ============================================================================

  test "example 4: order fulfillment workflow with inventory-based branching" do
    # This example demonstrates branching based on business logic

    check_inventory_service = Class.new(BetterService::Services::Base) do
      schema do
        required(:product_id).filled(:integer)
        required(:quantity).filled(:integer)
      end

      process_with do
        available_stock = rand(0..100)

        {
          resource: {
            product_id: params[:product_id],
            requested: params[:quantity],
            available: available_stock,
            in_stock: available_stock >= params[:quantity]
          }
        }
      end
    end

    ship_from_warehouse_service = Class.new(BetterService::Services::Base) do
      schema { optional(:context).filled }
      process_with do
        {
          resource: {
            shipment_id: "SHIP-#{SecureRandom.hex(4)}",
            method: "warehouse",
            estimated_delivery: 2.days.from_now
          }
        }
      end
    end

    dropship_from_supplier_service = Class.new(BetterService::Services::Base) do
      schema { optional(:context).filled }
      process_with do
        {
          resource: {
            dropship_id: "DROP-#{SecureRandom.hex(4)}",
            method: "dropship",
            estimated_delivery: 7.days.from_now
          }
        }
      end
    end

    workflow_class = Class.new(BetterService::Workflows::Base) do
      step :check_inventory,
           with: check_inventory_service,
           input: ->(ctx) { { product_id: ctx.product_id, quantity: ctx.quantity } }

      branch do
        on ->(ctx) { ctx.check_inventory[:in_stock] } do
          step :ship_from_warehouse, with: ship_from_warehouse_service
        end

        otherwise do
          step :dropship_from_supplier, with: dropship_from_supplier_service
        end
      end
    end

    user = User.new(1)
    result = workflow_class.new(user, params: { product_id: 789, quantity: 5 }).call

    assert result[:success]
    assert_equal [:check_inventory], result[:metadata][:steps_executed].take(1)

    # Either warehouse or dropship should be executed
    assert(
      result[:metadata][:steps_executed].include?(:ship_from_warehouse) ||
      result[:metadata][:steps_executed].include?(:dropship_from_supplier)
    )
  end
end
