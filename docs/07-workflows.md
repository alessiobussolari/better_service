# Workflows

Learn how to orchestrate multiple services with workflows.

---

## What are Workflows?

### Purpose

Workflows combine services into multi-step processes with automatic rollback.

```ruby
# Without workflow - manual orchestration, no rollback
order = Order.create!(params)
Payment::ChargeService.new(user, params: { order_id: order.id }).call  # If this fails, order exists!

# With workflow - automatic rollback
class Order::CheckoutWorkflow < BetterService::Workflows::Base
  step :create_order, with: Order::CreateService
  step :charge_payment, with: Payment::ChargeService,
       rollback: ->(ctx) { Payment::RefundService.new(ctx.user, params: {...}).call }
end
```

--------------------------------

## Getting Started

### Generate a Workflow

Create a workflow with the generator.

```bash
rails g serviceable:workflow Order::Checkout
```

This creates:
- `app/workflows/order/checkout_workflow.rb`
- `test/workflows/order/checkout_workflow_test.rb`

--------------------------------

### Basic Workflow

A simple workflow with steps.

```ruby
class Order::CheckoutWorkflow < BetterService::Workflows::Base
  with_transaction true

  step :validate_cart,
       with: Cart::ValidateService,
       input: ->(ctx) { { cart_id: ctx.cart_id } }

  step :charge_payment,
       with: Payment::ChargeService,
       input: ->(ctx) { { amount: ctx.validate_cart.total } }

  step :create_order,
       with: Order::CreateService,
       input: ->(ctx) { { cart: ctx.validate_cart, charge: ctx.charge_payment } }
end

# Usage
result = Order::CheckoutWorkflow.new(current_user, params: { cart_id: 123 }).call
```

--------------------------------

## Step Configuration

### with: Option

Specify the service to execute.

```ruby
step :validate_cart,
     with: Cart::ValidateService  # Required
```

--------------------------------

### input: Option

Map context to service params.

```ruby
step :create_order,
     with: Order::CreateService,
     input: ->(ctx) {
       {
         cart_id: ctx.cart_id,              # From workflow params
         total: ctx.validate_cart.total,    # From previous step
         user_id: ctx.user.id               # From workflow user
       }
     }
```

--------------------------------

### rollback: Option

Define rollback logic for failures.

```ruby
step :charge_payment,
     with: Payment::ChargeService,
     rollback: ->(ctx) {
       # Called if a later step fails
       Payment::RefundService.new(
         ctx.user,
         params: { charge_id: ctx.charge_payment.id }
       ).call
     }
```

--------------------------------

### optional: Option

Allow step to fail without stopping workflow.

```ruby
step :send_notification,
     with: Notification::SendService,
     optional: true  # Workflow continues even if this fails
```

--------------------------------

### if: Option

Conditionally execute step.

```ruby
step :apply_discount,
     with: Discount::ApplyService,
     if: ->(ctx) { ctx.validate_cart.has_coupon? }
```

--------------------------------

## Context Object

### Accessing Context

The context shares data between steps.

```ruby
# Previous step results
ctx.validate_cart       # Result from step :validate_cart
ctx.charge_payment.id   # Nested access

# Workflow user
ctx.user                # The user passed to workflow

# Workflow params (as methods)
ctx.cart_id             # From params[:cart_id]
ctx.order_id            # From params[:order_id]
```

--------------------------------

### Manual Context Storage

Store additional data in context.

```ruby
step :process_data,
     with: ProcessService,
     input: ->(ctx) {
       ctx.custom_data = { extra: "value" }  # Store custom data
       { id: ctx.order_id }
     }

# Later steps can access
input: ->(ctx) { { data: ctx.custom_data } }
```

--------------------------------

## Conditional Branching

### Basic Branching

Execute different paths based on conditions.

```ruby
class Order::ProcessPaymentWorkflow < BetterService::Workflows::Base
  step :validate_order,
       with: Order::ValidateService

  branch do
    on ->(ctx) { ctx.validate_order.payment_method == "credit_card" } do
      step :charge_card,
           with: Payment::ChargeCardService
    end

    on ->(ctx) { ctx.validate_order.payment_method == "paypal" } do
      step :charge_paypal,
           with: Payment::ChargePaypalService
    end

    otherwise do
      step :manual_payment,
           with: Payment::ManualService
    end
  end

  step :complete_order,
       with: Order::CompleteService
end
```

--------------------------------

### Branch Rules

How branching works.

```ruby
# 1. First-match wins - conditions evaluated in order
# 2. Single path - only one branch executes
# 3. Otherwise optional - but error if nothing matches without otherwise
# 4. Can be nested - branches inside branches
# 5. Rollback aware - only executed branch steps roll back
```

--------------------------------

### Nested Branches

Complex decision trees.

```ruby
branch do
  on ->(ctx) { ctx.order.type == "subscription" } do
    branch do
      on ->(ctx) { ctx.user.premium? } do
        step :premium_flow, with: PremiumService
      end
      otherwise do
        step :standard_flow, with: StandardService
      end
    end
  end

  otherwise do
    step :one_time_flow, with: OneTimeService
  end
end
```

--------------------------------

## Lifecycle Callbacks

### Before and After Hooks

Execute code at workflow boundaries.

```ruby
class Order::CheckoutWorkflow < BetterService::Workflows::Base
  before_workflow do |context|
    Rails.logger.info "Starting checkout for user #{context.user.id}"
  end

  after_workflow do |context, result|
    if result[:success]
      Analytics.track("checkout_completed", user_id: context.user.id)
    else
      Analytics.track("checkout_failed", user_id: context.user.id)
    end
  end

  # steps...
end
```

--------------------------------

## Workflow Result

### Success Result

Structure of a successful workflow result.

```ruby
result = Order::CheckoutWorkflow.new(user, params: { cart_id: 123 }).call

result[:success]   # => true
result[:context]   # => Context with all step results
result[:metadata]  # => {
                   #      workflow: "Order::CheckoutWorkflow",
                   #      steps_executed: [:validate_cart, :charge_payment, :create_order],
                   #      branches_taken: [],
                   #      duration_ms: 1234.56
                   #    }
```

--------------------------------

### Failure Result

Structure of a failed workflow result.

```ruby
result[:success]   # => false
result[:error]     # => The error that caused failure
result[:context]   # => Context up to failure point
result[:metadata][:steps_executed]  # Steps that ran before failure
```

--------------------------------

## Error Handling

### Handling Workflow Errors

Catch workflow-specific errors.

```ruby
begin
  result = Order::CheckoutWorkflow.new(user, params: params).call
rescue BetterService::Errors::Workflowable::Runtime::StepExecutionError => e
  # A step failed
  Rails.logger.error "Step #{e.context[:step]} failed: #{e.message}"
rescue BetterService::Errors::Workflowable::Runtime::RollbackError => e
  # Rollback failed
  Rails.logger.error "Rollback failed: #{e.message}"
rescue BetterService::Errors::Configuration::InvalidConfigurationError => e
  # No matching branch
  Rails.logger.error "Workflow config error: #{e.message}"
end
```

--------------------------------

## Complete Example

### E-commerce Checkout

Full workflow with all features.

```ruby
class Order::CheckoutWorkflow < BetterService::Workflows::Base
  with_transaction true

  before_workflow do |ctx|
    Rails.logger.info "Starting checkout for cart #{ctx.cart_id}"
  end

  step :validate_cart,
       with: Cart::ValidateService,
       input: ->(ctx) { { cart_id: ctx.cart_id } }

  step :apply_coupon,
       with: Coupon::ApplyService,
       input: ->(ctx) { { cart: ctx.validate_cart, code: ctx.coupon_code } },
       if: ->(ctx) { ctx.coupon_code.present? },
       optional: true

  branch do
    on ->(ctx) { ctx.validate_cart.payment_method == "credit_card" } do
      step :charge_card,
           with: Payment::ChargeCardService,
           input: ->(ctx) { { amount: ctx.validate_cart.total } },
           rollback: ->(ctx) {
             Payment::RefundService.new(ctx.user, params: { id: ctx.charge_card.id }).call
           }
    end

    on ->(ctx) { ctx.validate_cart.payment_method == "paypal" } do
      step :charge_paypal,
           with: Payment::ChargePaypalService,
           input: ->(ctx) { { amount: ctx.validate_cart.total } },
           rollback: ->(ctx) {
             Payment::RefundPaypalService.new(ctx.user, params: { id: ctx.charge_paypal.id }).call
           }
    end
  end

  step :create_order,
       with: Order::CreateService,
       input: ->(ctx) {
         {
           cart: ctx.validate_cart,
           payment_id: ctx.charge_card&.id || ctx.charge_paypal&.id
         }
       }

  step :send_confirmation,
       with: Email::OrderConfirmationService,
       input: ->(ctx) { { order: ctx.create_order } },
       optional: true

  step :clear_cart,
       with: Cart::ClearService,
       input: ->(ctx) { { cart_id: ctx.cart_id } }

  after_workflow do |ctx, result|
    if result[:success]
      Analytics.track("order_completed", order_id: ctx.create_order.id)
    end
  end
end

# Usage
result = Order::CheckoutWorkflow.new(
  current_user,
  params: { cart_id: 123, coupon_code: "SAVE10" }
).call
```

--------------------------------

## Best Practices

### Workflow Guidelines

Follow these guidelines.

```ruby
# 1. Use transactions for write operations
with_transaction true

# 2. Define rollback for reversible operations
step :charge, with: ChargeService,
     rollback: ->(ctx) { RefundService.new(...).call }

# 3. Use optional for non-critical steps
step :notify, with: NotifyService, optional: true

# 4. Keep branches simple - use nested branches for complex logic
branch do
  on ->(ctx) { simple_condition } do
    # steps
  end
end

# 5. Log workflow execution
before_workflow { |ctx| Rails.logger.info "Starting #{self.class}" }
```

--------------------------------
