# Advanced Workflows Guide

This guide covers advanced workflow patterns, best practices, and real-world scenarios for composing complex multi-step business operations.

## Table of Contents

- [Overview](#overview)
- [Advanced Patterns](#advanced-patterns)
- [Error Recovery](#error-recovery)
- [Performance Optimization](#performance-optimization)
- [Complex Scenarios](#complex-scenarios)
- [Best Practices](#best-practices)

---

## Overview

Workflows allow you to compose multiple services into pipelines with:
- **Explicit data mapping** between steps
- **Conditional execution** based on context
- **Automatic rollback** on failure
- **Lifecycle hooks** for cross-cutting concerns
- **Transaction support** for atomicity

For basic workflow usage, see [Workflows Introduction](../workflows/01_workflows_introduction.md).

---

## Advanced Patterns

### Pattern 1: Conditional Step Chains

Execute different steps based on runtime conditions.

```ruby
class Order::ProcessWorkflow < BetterService::Workflow
  step :validate_order, with: Order::ValidateService

  # Branch based on payment method
  step :charge_card,
       with: Payment::ChargeCardService,
       input: ->(ctx) { { order: ctx.order } },
       if: ->(ctx) { ctx.order.payment_method == "card" }

  step :process_paypal,
       with: Payment::PayPalService,
       input: ->(ctx) { { order: ctx.order } },
       if: ->(ctx) { ctx.order.payment_method == "paypal" }

  step :process_crypto,
       with: Payment::CryptoService,
       input: ->(ctx) { { order: ctx.order } },
       if: ->(ctx) { ctx.order.payment_method == "crypto" }

  # Continue with common steps
  step :fulfill_order, with: Order::FulfillService
  step :send_confirmation, with: Email::ConfirmationService
end
```

---

### Pattern 2: Dynamic Step Configuration

Generate steps dynamically based on input.

```ruby
class Product::BulkUpdateWorkflow < BetterService::Workflow
  before_workflow :setup_steps

  private

  def setup_steps(context)
    products = Product.where(id: context.product_ids)

    products.each do |product|
      step :"update_product_#{product.id}",
           with: Product::UpdateService,
           input: ->(ctx) { { id: product.id, **ctx.params } }
    end
  end
end
```

---

### Pattern 3: Parallel Step Execution

Execute independent steps in parallel (requires concurrent processing).

```ruby
class Order::CompleteWorkflow < BetterService::Workflow
  step :create_order, with: Order::CreateService

  # These steps can run in parallel
  step :charge_payment,
       with: Payment::ChargeService,
       input: ->(ctx) { { order: ctx.order } }

  step :reserve_inventory,
       with: Inventory::ReserveService,
       input: ->(ctx) { { items: ctx.order.items } }

  step :send_notification,
       with: Email::NotificationService,
       input: ->(ctx) { { order: ctx.order } },
       optional: true  # Don't fail workflow if email fails

  # Wait for all parallel steps before continuing
  step :finalize_order,
       with: Order::FinalizeService,
       input: ->(ctx) {
         {
           order: ctx.order,
           charge: ctx.charge_payment,
           reservation: ctx.reserve_inventory
         }
       }
end
```

---

### Pattern 4: Nested Workflows

Workflows can call other workflows.

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  step :validate_cart, with: Cart::ValidateService

  # Call another workflow as a step
  step :process_payment,
       with: Payment::ProcessWorkflow,  # Another workflow
       input: ->(ctx) { { cart: ctx.cart, user: ctx.user } }

  step :create_order, with: Order::CreateService
  step :clear_cart, with: Cart::ClearService
end

class Payment::ProcessWorkflow < BetterService::Workflow
  step :validate_payment_method, with: Payment::ValidateService
  step :charge_card, with: Payment::ChargeService
  step :record_transaction, with: Payment::RecordService
end
```

---

### Pattern 5: Saga Pattern (Distributed Transactions)

Implement sagas with compensating transactions.

```ruby
class Order::DistributedCheckoutWorkflow < BetterService::Workflow
  with_transaction false  # No DB transaction, using saga

  step :reserve_inventory,
       with: Inventory::ReserveService,
       input: ->(ctx) { { items: ctx.cart_items } },
       rollback: ->(ctx) {
         # Compensating transaction: release inventory
         Inventory::ReleaseService.new(ctx.user, params: {
           reservation_id: ctx.reserve_inventory.id
         }).call
       }

  step :charge_payment,
       with: Payment::ChargeService,
       input: ->(ctx) { { amount: ctx.cart_total } },
       rollback: ->(ctx) {
         # Compensating transaction: refund payment
         Payment::RefundService.new(ctx.user, params: {
           charge_id: ctx.charge_payment.id
         }).call
       }

  step :ship_order,
       with: Shipping::CreateShipmentService,
       input: ->(ctx) { { order: ctx.order } },
       rollback: ->(ctx) {
         # Compensating transaction: cancel shipment
         Shipping::CancelService.new(ctx.user, params: {
           shipment_id: ctx.ship_order.id
         }).call
       }

  step :send_confirmation,
       with: Email::ConfirmationService,
       optional: true  # Email failure doesn't trigger rollback
end
```

---

## Error Recovery

### Pattern 1: Retry Failed Steps

```ruby
class Order::ProcessWorkflow < BetterService::Workflow
  around_step :retry_on_failure

  step :charge_payment, with: Payment::ChargeService

  private

  def retry_on_failure(step, context)
    retries = 0
    max_retries = 3

    begin
      yield
    rescue StandardError => e
      retries += 1

      if retries <= max_retries
        sleep(2**retries)  # Exponential backoff
        retry
      else
        raise  # Re-raise after max retries
      end
    end
  end
end
```

---

### Pattern 2: Fallback Steps

```ruby
class Payment::ProcessWorkflow < BetterService::Workflow
  step :charge_primary,
       with: Payment::ChargePrimaryService,
       input: ->(ctx) { { amount: ctx.amount } }

  # Fallback if primary fails
  step :charge_fallback,
       with: Payment::ChargeFallbackService,
       input: ->(ctx) { { amount: ctx.amount } },
       if: ->(ctx) { ctx.charge_primary.nil? }  # Only if primary failed
end
```

---

### Pattern 3: Circuit Breaker

```ruby
class ExternalAPI::ProcessWorkflow < BetterService::Workflow
  before_workflow :check_circuit_breaker

  step :call_external_api,
       with: ExternalAPI::CallService

  private

  def check_circuit_breaker(context)
    breaker = CircuitBreaker.get("external_api")

    if breaker.open?
      context.fail!("External API circuit breaker is open")
    end
  end

  def log_completion(context)
    if context.failure?
      CircuitBreaker.get("external_api").record_failure
    else
      CircuitBreaker.get("external_api").record_success
    end
  end
end
```

---

## Performance Optimization

### Pattern 1: Lazy Loading

Only load data when needed by specific steps.

```ruby
class Order::CompleteWorkflow < BetterService::Workflow
  step :create_order, with: Order::CreateService

  # Load user only if premium
  step :send_premium_email,
       with: Email::PremiumService,
       input: ->(ctx) {
         # Lazy load user details only when needed
         user = User.includes(:preferences).find(ctx.user.id)
         { user: user, order: ctx.order }
       },
       if: ->(ctx) { ctx.user.premium? }
end
```

---

### Pattern 2: Batch Processing

Process multiple items in batches.

```ruby
class Product::BulkImportWorkflow < BetterService::Workflow
  step :import_products, with: Product::ImportService

  private

  def import_products(context)
    context.csv_rows.each_slice(100) do |batch|
      Product.import(batch)  # Bulk insert
    end
  end
end
```

---

### Pattern 3: Background Processing

Move slow steps to background jobs.

```ruby
class Order::CompleteWorkflow < BetterService::Workflow
  step :create_order, with: Order::CreateService
  step :charge_payment, with: Payment::ChargeService

  # Synchronous critical steps above
  # Background non-critical steps below

  after_workflow :queue_background_tasks

  private

  def queue_background_tasks(context)
    return unless context.success?

    # Queue email in background
    EmailJob.perform_later(context.order.id)

    # Queue analytics in background
    AnalyticsJob.perform_later(context.order.id)
  end
end
```

---

## Complex Scenarios

### Scenario 1: Multi-Tenant SaaS Onboarding

```ruby
class Account::OnboardingWorkflow < BetterService::Workflow
  with_transaction true

  # Step 1: Create tenant account
  step :create_account,
       with: Account::CreateService,
       input: ->(ctx) { { name: ctx.params[:account_name] } }

  # Step 2: Setup database schema
  step :setup_schema,
       with: Account::SetupSchemaService,
       input: ->(ctx) { { account: ctx.create_account } },
       rollback: ->(ctx) {
         Account::DropSchemaService.new(ctx.user, params: {
           account: ctx.create_account
         }).call
       }

  # Step 3: Create admin user
  step :create_admin,
       with: User::CreateService,
       input: ->(ctx) {
         {
           email: ctx.params[:admin_email],
           account: ctx.create_account,
           role: "admin"
         }
       }

  # Step 4: Setup billing
  step :setup_billing,
       with: Billing::SetupService,
       input: ->(ctx) {
         {
           account: ctx.create_account,
           payment_method: ctx.params[:payment_method]
         }
       },
       rollback: ->(ctx) {
         Billing::CancelService.new(ctx.user, params: {
           account: ctx.create_account
         }).call
       }

  # Step 5: Send welcome email
  step :send_welcome,
       with: Email::WelcomeService,
       input: ->(ctx) { { user: ctx.create_admin } },
       optional: true

  after_workflow :log_onboarding

  private

  def log_onboarding(context)
    if context.success?
      Rails.logger.info("Account onboarded: #{context.create_account.id}")
    else
      Rails.logger.error("Onboarding failed: #{context.errors}")
    end
  end
end
```

---

### Scenario 2: E-commerce Order Processing

```ruby
class Order::ProcessWorkflow < BetterService::Workflow
  with_transaction true

  before_workflow :validate_cart
  after_workflow :clear_cart_on_success

  # Validation
  step :validate_stock,
       with: Inventory::ValidateStockService,
       input: ->(ctx) { { items: ctx.cart.items } }

  # Payment
  step :calculate_total,
       with: Order::CalculateTotalService,
       input: ->(ctx) { { cart: ctx.cart, coupon: ctx.params[:coupon] } }

  step :charge_payment,
       with: Payment::ChargeService,
       input: ->(ctx) {
         {
           amount: ctx.calculate_total.total,
           payment_method: ctx.params[:payment_method]
         }
       },
       rollback: ->(ctx) {
         Payment::RefundService.new(ctx.user, params: {
           charge_id: ctx.charge_payment.id
         }).call if ctx.charge_payment
       }

  # Order creation
  step :create_order,
       with: Order::CreateService,
       input: ->(ctx) {
         {
           cart: ctx.cart,
           charge: ctx.charge_payment,
           total: ctx.calculate_total.total
         }
       }

  # Fulfillment
  step :reserve_inventory,
       with: Inventory::ReserveService,
       input: ->(ctx) { { order: ctx.create_order } },
       rollback: ->(ctx) {
         Inventory::ReleaseService.new(ctx.user, params: {
           order: ctx.create_order
         }).call if ctx.create_order
       }

  step :create_shipment,
       with: Shipping::CreateService,
       input: ->(ctx) { { order: ctx.create_order } },
       if: ->(ctx) { ctx.create_order.requires_shipping? }

  # Notifications
  step :send_confirmation,
       with: Email::OrderConfirmationService,
       input: ->(ctx) { { order: ctx.create_order } },
       optional: true

  step :notify_admin,
       with: Admin::NotifyNewOrderService,
       input: ->(ctx) { { order: ctx.create_order } },
       optional: true,
       if: ->(ctx) { ctx.create_order.total > 1000 }

  private

  def validate_cart(context)
    context.fail!("Cart is empty") if context.cart.empty?
  end

  def clear_cart_on_success(context)
    context.cart.clear! if context.success?
  end
end
```

---

## Best Practices

### 1. Keep Workflows Focused

Each workflow should represent a single business process.

```ruby
# ✅ Good - focused workflows
class Order::CheckoutWorkflow < BetterService::Workflow
  # Only checkout-related steps
end

class Order::FulfillmentWorkflow < BetterService::Workflow
  # Only fulfillment-related steps
end

# ❌ Bad - too many responsibilities
class Order::ProcessEverythingWorkflow < BetterService::Workflow
  # Checkout, fulfillment, refunds, everything...
end
```

---

### 2. Use Explicit Input Mapping

Always explicitly map data from context to service params.

```ruby
# ✅ Good - explicit mapping
step :charge_payment,
     with: Payment::ChargeService,
     input: ->(ctx) {
       {
         amount: ctx.order.total,
         payment_method: ctx.payment_method
       }
     }

# ❌ Bad - implicit, unclear
step :charge_payment,
     with: Payment::ChargeService,
     input: ->(ctx) { ctx.to_h }
```

---

### 3. Make Rollback Idempotent

Rollback logic should be safe to run multiple times.

```ruby
# ✅ Good - idempotent rollback
rollback: ->(ctx) {
  charge = Charge.find_by(id: ctx.charge_payment&.id)
  charge.refund! if charge && !charge.refunded?
}

# ❌ Bad - not idempotent
rollback: ->(ctx) {
  Charge.find(ctx.charge_payment.id).refund!  # Fails if already refunded
}
```

---

### 4. Use Optional for Non-Critical Steps

Don't fail workflows for non-essential operations.

```ruby
# ✅ Good - optional for emails, analytics
step :send_email,
     with: Email::Service,
     optional: true

# ❌ Bad - critical steps shouldn't be optional
step :charge_payment,
     with: Payment::ChargeService,
     optional: true  # Never do this!
```

---

### 5. Document Step Dependencies

```ruby
class Order::ProcessWorkflow < BetterService::Workflow
  # STEP DEPENDENCIES:
  # - create_order → charge_payment (needs order.total)
  # - charge_payment → send_receipt (needs charge.id)
  # - reserve_inventory → create_order (needs order.items)

  step :create_order, with: Order::CreateService
  step :charge_payment, with: Payment::ChargeService
  step :reserve_inventory, with: Inventory::ReserveService
  step :send_receipt, with: Email::ReceiptService
end
```

---

### 6. Test Workflows Thoroughly

Test success path, failure paths, and rollback logic.

```ruby
class Order::ProcessWorkflowTest < ActiveSupport::TestCase
  test "successful checkout" do
    result = Order::ProcessWorkflow.new(user, params: valid_params).call

    assert result[:success]
    assert result[:context].order.present?
  end

  test "rollback on payment failure" do
    Payment::ChargeService.stub(:call, -> { raise "Payment failed" }) do
      result = Order::ProcessWorkflow.new(user, params: valid_params).call

      assert result[:failure]
      assert_nil Order.last  # Order was rolled back
    end
  end
end
```

---

## Next Steps

- **[Workflows Introduction](../workflows/01_workflows_introduction.md)** - Basic workflow concepts
- **[Workflow Steps](../workflows/02_workflow_steps.md)** - Step configuration
- **[Workflow Examples](../workflows/05_workflow_examples.md)** - More examples
- **[Error Handling](error-handling.md)** - Handling workflow errors

---

**See Also:**
- [Getting Started](../start/getting-started.md)
- [Service Types](../services/01_services_structure.md)
- [Testing Guide](../testing.md)
