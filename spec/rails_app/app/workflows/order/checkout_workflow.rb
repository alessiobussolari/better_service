# frozen_string_literal: true

class Order::CheckoutWorkflow < BetterService::Workflows::Base
  with_transaction true

  # Step 1: Validate the order exists and can be checked out
  step :validate_order,
       with: Order::ValidateService,
       input: ->(ctx) { { id: ctx.order_id } }

  # Step 2: Reserve inventory for all items
  step :reserve_inventory,
       with: Inventory::ReserveService,
       input: ->(ctx) { { order_id: ctx.validate_order.id } },
       rollback: ->(ctx) {
         Inventory::ReleaseService.new(ctx.user, params: { order_id: ctx.validate_order.id }).call
       }

  # Step 3: Create payment record
  step :create_payment,
       with: Payment::CreateService,
       input: ->(ctx) { { order_id: ctx.validate_order.id, provider: ctx.payment_provider } },
       rollback: ->(ctx) {
         # Payment will be cancelled automatically with order cancellation
       }

  # Step 4: Start payment processing
  step :process_payment,
       with: Payment::ProcessService,
       input: ->(ctx) { { payment_id: ctx.create_payment.id } }

  # Step 5: Branch based on payment provider
  branch do
    # Stripe credit card processing
    on ->(ctx) { ctx.create_payment.stripe? } do
      step :charge_stripe,
           with: Payment::Stripe::ChargeService,
           input: ->(ctx) { { payment_id: ctx.create_payment.id, card_token: ctx.card_token } },
           rollback: ->(ctx) {
             Payment::RefundService.new(ctx.user, params: { payment_id: ctx.create_payment.id, reason: "Checkout failed" }).call rescue nil
           }
    end

    # PayPal processing
    on ->(ctx) { ctx.create_payment.paypal? } do
      step :charge_paypal,
           with: Payment::Paypal::ChargeService,
           input: ->(ctx) { { payment_id: ctx.create_payment.id, paypal_order_id: ctx.paypal_order_id } },
           rollback: ->(ctx) {
             Payment::RefundService.new(ctx.user, params: { payment_id: ctx.create_payment.id, reason: "Checkout failed" }).call rescue nil
           }
    end

    # Bank transfer (manual confirmation)
    on ->(ctx) { ctx.create_payment.bank? } do
      step :initiate_bank_transfer,
           with: Payment::Bank::TransferService,
           input: ->(ctx) { { payment_id: ctx.create_payment.id } }
    end

    # Fallback for unknown providers
    otherwise do
      step :unknown_provider,
           with: Payment::ProcessService,
           input: ->(ctx) { { payment_id: ctx.create_payment.id } }
    end
  end

  # Step 6: Confirm the order after payment
  step :confirm_order,
       with: Order::ConfirmService,
       input: ->(ctx) { { id: ctx.validate_order.id } }

  # Step 7: Send confirmation email (optional, doesn't fail workflow)
  step :send_confirmation,
       with: Notification::OrderConfirmationService,
       input: ->(ctx) { { order_id: ctx.validate_order.id, email: ctx.user.email } },
       optional: true
end
