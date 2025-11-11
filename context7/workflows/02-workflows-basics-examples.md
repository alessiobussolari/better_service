# Workflow Basics Examples

## Simple Workflow
Compose multiple services in sequence.

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  schema do
    required(:cart_id).filled(:integer)
    required(:payment_method).filled(:string)
  end

  step :create_order, with: Order::CreateService
  step :charge_payment, with: Payment::ChargeService
  step :send_confirmation, with: Email::ConfirmationService
end

# Usage
result = Order::CheckoutWorkflow.new(current_user, params: {
  cart_id: 123,
  payment_method: 'card'
}).call

order = result[:order]
```

## Generate a Workflow
Create workflow using generator.

```bash
rails g serviceable:workflow Order::Checkout
```

This creates:
```ruby
# app/workflows/order/checkout_workflow.rb
module Order
  class CheckoutWorkflow < BetterService::Workflow
    schema do
      # Define your parameters
    end

    # Add steps
    step :step_one, with: StepOneService
    step :step_two, with: StepTwoService
  end
end
```

## Step with Parameters
Map workflow context to service parameters.

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  schema do
    required(:cart_id).filled(:integer)
  end

  step :create_order,
       with: Order::CreateService,
       params: ->(context) {
         {
           cart_id: context[:cart_id],
           user_id: context[:user_id]
         }
       }

  step :charge_payment,
       with: Payment::ChargeService,
       params: ->(context) {
         {
           order_id: context[:order].id,
           amount: context[:order].total
         }
       }
end
```

## Conditional Step
Execute step only when condition is met.

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  schema do
    required(:cart_id).filled(:integer)
    optional(:coupon_code).maybe(:string)
  end

  step :create_order, with: Order::CreateService

  # Only apply coupon if code is provided
  step :apply_coupon,
       with: Order::ApplyCouponService,
       if: ->(context) { context[:coupon_code].present? }

  step :charge_payment, with: Payment::ChargeService
end
```

## Workflow with Authorization
Restrict workflow execution.

```ruby
class Order::RefundWorkflow < BetterService::Workflow
  authorize_with do
    user.admin? || user.customer_service?
  end

  schema do
    required(:order_id).filled(:integer)
  end

  step :validate_refund, with: Order::ValidateRefundService
  step :process_refund, with: Payment::RefundService
  step :send_notification, with: Email::RefundNotificationService
end
```

## Automatic Rollback
All steps roll back if any fails.

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
  flash[:error] = "Payment failed: #{e.message}"
end
```

## Context Accumulation
Each step adds to the context.

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
  # Context after: { user: #<User>, profile: #<Profile>, resource: true }
end

# Final result contains all keys from all steps
```

## Error Handling in Steps
Log errors while still failing.

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  step :charge_payment,
       with: Payment::ChargeService,
       on_error: ->(context, error) {
         # Log the error
         PaymentLogger.log_failure(context[:order], error)

         # Track metric
         Metrics.increment('payment.failures')

         # Error still bubbles up and causes rollback
       }
end
```

## Simple E-commerce Checkout
Complete checkout flow.

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
  end

  step :create_order,
       with: Order::CreateFromCartService

  step :calculate_shipping,
       with: Order::CalculateShippingService,
       params: ->(context) {
         {
           order_id: context[:order].id,
           address: context[:shipping_address]
         }
       }

  step :charge_payment,
       with: Payment::ChargeService,
       params: ->(context) {
         {
           order_id: context[:order].id,
           amount: context[:order].reload.total,
           payment_method: context[:payment_method]
         }
       }

  step :confirm_order,
       with: Order::ConfirmService

  step :clear_cart,
       with: Cart::ClearService

  step :send_confirmation,
       with: Email::OrderConfirmationService
end
```
