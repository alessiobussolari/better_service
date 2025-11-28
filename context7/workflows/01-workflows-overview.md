# Workflows Overview

## What are Workflows?

Workflows compose multiple services into a single transaction. If any step fails, all changes are automatically rolled back.

## Why Use Workflows?

### ❌ ANTI-PATTERN: Calling Services from Services

```ruby
# ❌ NEVER DO THIS
class Order::CreateService < BetterService::CreateService
  process_with do |data|
    order = Order.create!(params)

    # ❌ Calling another service - NO automatic rollback!
    Payment::ChargeService.new(user, params: { order_id: order.id }).call

    { resource: order }
  end
end
```

**Problems:**
- No automatic rollback if payment fails
- Order is already created in database
- Tight coupling between services
- Difficult to test individually

### ✅ CORRECT: Use Workflows

```ruby
# ✅ CORRECT APPROACH
class Order::CheckoutWorkflow < BetterService::Workflow
  schema do
    required(:cart_id).filled(:integer)
    required(:payment_method).filled(:string)
  end

  step :create_order, with: Order::CreateService
  step :charge_payment, with: Payment::ChargeService
  step :send_confirmation, with: Email::ConfirmationService
end
```

**Benefits:**
- ✅ Automatic rollback if any step fails
- ✅ All steps wrapped in single transaction
- ✅ Services remain independent and testable

## Conditional Branching (v1.1.0+)

Workflows support **conditional branching** for multi-path execution:

```ruby
class Payment::ProcessWorkflow < BetterService::Workflow
  step :validate_order, with: Order::ValidateService

  # Branch based on payment method - only one path executes
  branch do
    on ->(ctx) { ctx.validate_order.payment_method == 'credit_card' } do
      step :charge_card, with: Payment::ChargeCreditCardService
      step :verify_3d_secure, with: Payment::Verify3DSecureService
    end

    on ->(ctx) { ctx.validate_order.payment_method == 'paypal' } do
      step :charge_paypal, with: Payment::ChargePayPalService
    end

    otherwise do
      step :manual_review, with: Payment::ManualReviewService
    end
  end

  step :finalize_order, with: Order::FinalizeService
end
```

**Branch DSL:**
- `branch do ... end` - Define branch group
- `on ->(ctx) { condition }` - Conditional path (first match wins)
- `otherwise do ... end` - Default path

**Key features:**
- First-match semantics (like case/when)
- Only executed branch is rolled back on failure
- Unlimited nesting depth
- Metadata tracks branches taken: `result[:metadata][:branches_taken]`
- ✅ Clear, declarative flow

## Basic Workflow Example

### Generate Workflow

```bash
rails g serviceable:workflow Order::Checkout
```

### Define Steps

```ruby
module Order
  class CheckoutWorkflow < BetterService::Workflow
    schema do
      required(:cart_id).filled(:integer)
      required(:payment_method).filled(:string)
    end

    # Steps execute in order
    step :create_order, with: Order::CreateService
    step :charge_payment, with: Payment::ChargeService
    step :clear_cart, with: Cart::ClearService
    step :send_confirmation, with: Email::ConfirmationService
  end
end
```

### Use Workflow

```ruby
# In controller
result = Order::CheckoutWorkflow.new(current_user, params: {
  cart_id: 123,
  payment_method: 'card'
}).call

order = result[:order]
```

## Step Features

### Parameter Mapping

```ruby
step :charge_payment,
     with: Payment::ChargeService,
     params: ->(context) {
       {
         order_id: context[:order].id,
         amount: context[:order].total
       }
     }
```

### Conditional Execution

```ruby
step :apply_coupon,
     with: Order::ApplyCouponService,
     if: ->(context) { context[:coupon_code].present? }

step :charge_shipping,
     with: Order::ChargeShippingService,
     unless: ->(context) { context[:order].free_shipping? }
```

### Error Handling

```ruby
step :charge_payment,
     with: Payment::ChargeService,
     on_error: ->(context, error) {
       # Log error (rollback still happens)
       PaymentLogger.log_failure(context[:order], error)
       Metrics.increment('payment.failures')
     }
```

## Automatic Rollback

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  step :create_order, with: Order::CreateService  # ✓ Creates order (id: 123)
  step :charge_payment, with: Payment::ChargeService  # ✗ Fails - card declined

  # Automatic rollback:
  # - Order (id: 123) is deleted
  # - Database returns to original state
  # - Error is raised to caller
end

# Usage
begin
  result = Order::CheckoutWorkflow.new(user, params: checkout_params).call
rescue BetterService::Errors::Runtime::ExecutionError => e
  # Payment failed, nothing was committed
  flash[:error] = "Checkout failed: #{e.message}"
end
```

## Context Accumulation

Each step adds data to the workflow context:

```ruby
class User::RegistrationWorkflow < BetterService::Workflow
  step :create_user, with: User::CreateService
  # Context after: { user: #<User> }

  step :create_profile,
       with: Profile::CreateService,
       params: ->(context) {
         { user_id: context[:user].id }
       }
  # Context after: { user: #<User>, profile: #<Profile> }

  step :send_welcome,
       with: Email::WelcomeService,
       params: ->(context) {
         { user_id: context[:user].id }
       }
  # Context after: { user: #<User>, profile: #<Profile>, email_sent: true }
end

# Final result contains all keys from all steps
result = workflow.call
result[:user]     # Available
result[:profile]  # Available
```

## Real-World Example

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  schema do
    required(:cart_id).filled(:integer)
    required(:payment_method).filled(:string)
    required(:shipping_address).hash do
      required(:street).filled(:string)
      required(:city).filled(:string)
      required(:zip).filled(:string)
    end
    optional(:coupon_code).maybe(:string)
  end

  # Always execute
  step :create_order, with: Order::CreateFromCartService

  # Conditional: only if coupon provided
  step :apply_coupon,
       with: Order::ApplyCouponService,
       if: ->(context) { context[:coupon_code].present? }

  # Calculate shipping based on address
  step :calculate_shipping,
       with: Order::CalculateShippingService,
       params: ->(context) {
         {
           order_id: context[:order].id,
           address: context[:shipping_address]
         }
       }

  # Charge payment
  step :charge_payment,
       with: Payment::ChargeService,
       params: ->(context) {
         {
           order_id: context[:order].id,
           amount: context[:order].reload.total,
           payment_method: context[:payment_method]
         }
       },
       on_error: ->(context, error) {
         PaymentLogger.log_failure(context[:order], error)
       }

  # Confirm order
  step :confirm_order, with: Order::ConfirmService

  # Clear cart
  step :clear_cart, with: Cart::ClearService

  # Send confirmation
  step :send_confirmation, with: Email::OrderConfirmationService
end
```

## When to Use Workflows

Use workflows when you need to:
- Execute multiple services in sequence
- Ensure all-or-nothing behavior (transactions)
- Compose complex business processes
- Share data between services
- Handle errors with automatic rollback

## Next Steps

- **Basic Examples**: See `02-workflows-basics-examples.md`
- **Step Configuration**: See `03-workflows-steps.md`
- **Real Patterns**: See `04-workflows-patterns.md`
