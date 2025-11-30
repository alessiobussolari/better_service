# Workflows

Build multi-step business processes with orchestration.

---

## Why Workflows?

### Never Call Services from Services

Use workflows instead of nesting service calls.

```ruby
# WRONG: Calling service from service
class Order::CreateService < Order::BaseService
  process_with do |data|
    order = order_repository.create!(params)

    # DON'T DO THIS - No rollback support!
    Payment::ChargeService.new(user, params: { order: order }).call
    Inventory::ReserveService.new(user, params: { order: order }).call
    Email::ConfirmationService.new(user, params: { order: order }).call

    { resource: order }
  end
end

# CORRECT: Use a workflow
class Order::CheckoutWorkflow < BetterService::Workflows::Base
  with_transaction true

  step :create_order, with: Order::CreateService
  step :charge_payment, with: Payment::ChargeService, rollback: ...
  step :reserve_inventory, with: Inventory::ReserveService
  step :send_email, with: Email::ConfirmationService, optional: true
end
```

--------------------------------

## Basic Workflow

### Simple Linear Workflow

Create a workflow that executes steps in order.

```ruby
class Order::CheckoutWorkflow < BetterService::Workflows::Base
  with_transaction true

  step :validate_cart,
       with: Cart::ValidateService,
       input: ->(ctx) { { cart_id: ctx.cart_id } }

  step :create_order,
       with: Order::CreateService,
       input: ->(ctx) { { cart: ctx.validate_cart } }

  step :charge_payment,
       with: Payment::ChargeService,
       input: ->(ctx) { { order: ctx.create_order, amount: ctx.create_order.total } }

  step :send_confirmation,
       with: Email::OrderConfirmationService,
       input: ->(ctx) { { order: ctx.create_order } }
end

# Usage
result = Order::CheckoutWorkflow.new(
  current_user,
  params: { cart_id: 123 }
).call
```

--------------------------------

## Step Configuration

### Step Options

Configure each step with options.

```ruby
step :step_name,
     with: ServiceClass,           # Required: service to execute
     input: ->(ctx) { {...} },     # Optional: params for service
     rollback: ->(ctx) { ... },    # Optional: undo action
     optional: true                 # Optional: don't fail on error
```

--------------------------------

### Input Lambda

Pass data from context to each step.

```ruby
step :create_order,
     with: Order::CreateService,
     input: ->(ctx) {
       {
         user_id: ctx.user.id,
         cart: ctx.validate_cart,
         total: ctx.validate_cart.total,
         items: ctx.validate_cart.items
       }
     }
```

--------------------------------

### Optional Steps

Mark steps that can fail without stopping the workflow.

```ruby
step :send_email,
     with: Email::NotificationService,
     input: ->(ctx) { { order: ctx.create_order } },
     optional: true  # Workflow continues if email fails

step :log_analytics,
     with: Analytics::TrackService,
     input: ->(ctx) { { event: "order_created" } },
     optional: true  # Non-critical step
```

--------------------------------

## Context Object

### Accessing Context

Steps store results in context automatically.

```ruby
# Service returns: { resource: order }
# Stored as: ctx.create_order (step name)

step :create_order, with: Order::CreateService

# Access in next step
step :charge_payment,
     with: Payment::ChargeService,
     input: ->(ctx) {
       {
         order_id: ctx.create_order.id,      # Access step result
         amount: ctx.create_order.total,
         user: ctx.user                       # Access workflow user
       }
     }
```

--------------------------------

### Context Methods

Available context operations.

```ruby
input: ->(ctx) {
  # Access step results by name
  ctx.step_name           # Get result of step :step_name

  # Access user
  ctx.user                # The user passed to workflow

  # Access initial params
  ctx.cart_id             # From params: { cart_id: 123 }

  # Dynamic attributes
  ctx.add(:key, value)    # Store additional data
  ctx.get(:key)           # Retrieve stored data

  { ... }
}
```

--------------------------------

## Branching

### Conditional Execution

Execute different steps based on conditions.

```ruby
class Order::ProcessPaymentWorkflow < BetterService::Workflows::Base
  with_transaction true

  step :validate_order,
       with: Order::ValidateService,
       input: ->(ctx) { { order_id: ctx.order_id } }

  branch do
    on ->(ctx) { ctx.validate_order.payment_method == "credit_card" } do
      step :charge_card,
           with: Payment::CreditCardService,
           input: ->(ctx) { { order: ctx.validate_order } }
    end

    on ->(ctx) { ctx.validate_order.payment_method == "paypal" } do
      step :charge_paypal,
           with: Payment::PaypalService,
           input: ->(ctx) { { order: ctx.validate_order } }
    end

    otherwise do
      step :process_bank_transfer,
           with: Payment::BankTransferService,
           input: ->(ctx) { { order: ctx.validate_order } }
    end
  end

  step :confirm_order,
       with: Order::ConfirmService,
       input: ->(ctx) { { order: ctx.validate_order } }
end
```

--------------------------------

### Branch Rules

Important rules for branching.

```ruby
branch do
  # 1. First matching condition wins
  on ->(ctx) { condition1 } do
    # Executes if condition1 is true
  end

  on ->(ctx) { condition2 } do
    # Only checked if condition1 was false
  end

  # 2. Otherwise is optional but recommended
  otherwise do
    # Executes if no conditions match
    # Without otherwise: raises error if no match
  end
end
```

--------------------------------

### Nested Branches

Branches can contain other branches.

```ruby
class Document::ApprovalWorkflow < BetterService::Workflows::Base
  step :validate, with: Document::ValidateService

  branch do
    on ->(ctx) { ctx.validate.type == "contract" } do
      step :legal_review, with: Legal::ReviewService

      # Nested branch
      branch do
        on ->(ctx) { ctx.validate.value > 100_000 } do
          step :ceo_approval, with: Approval::CEOService
        end

        otherwise do
          step :manager_approval, with: Approval::ManagerService
        end
      end
    end

    on ->(ctx) { ctx.validate.type == "invoice" } do
      step :finance_review, with: Finance::ReviewService
    end

    otherwise do
      step :standard_approval, with: Approval::StandardService
    end
  end

  step :finalize, with: Document::FinalizeService
end
```

--------------------------------

## Rollback

### Define Rollback Actions

Specify how to undo a step on failure.

```ruby
step :charge_payment,
     with: Payment::ChargeService,
     input: ->(ctx) { { amount: ctx.order.total } },
     rollback: ->(ctx) {
       Payment::RefundService.new(
         ctx.user,
         params: { charge_id: ctx.charge_payment.id }
       ).call
     }

step :reserve_inventory,
     with: Inventory::ReserveService,
     input: ->(ctx) { { order: ctx.order } },
     rollback: ->(ctx) {
       Inventory::ReleaseService.new(
         ctx.user,
         params: { reservation_id: ctx.reserve_inventory.id }
       ).call
     }
```

--------------------------------

### Rollback Order

Rollbacks execute in reverse order (LIFO).

```ruby
# If step 3 fails:
# 1. Rollback step 2 (if has rollback)
# 2. Rollback step 1 (if has rollback)
# 3. Transaction rolls back (if with_transaction true)

class Order::CheckoutWorkflow < BetterService::Workflows::Base
  with_transaction true

  step :create_order, with: Order::CreateService  # Step 1

  step :charge_payment,                            # Step 2
       with: Payment::ChargeService,
       rollback: ->(ctx) { ... }

  step :reserve_inventory,                         # Step 3 - fails here
       with: Inventory::ReserveService,
       rollback: ->(ctx) { ... }

  # If step 3 fails:
  # → rollback step 2 (charge_payment)
  # → step 1 rolled back by transaction
end
```

--------------------------------

## Transaction Support

### Wrap in Database Transaction

Enable database transaction for the workflow.

```ruby
class Order::CheckoutWorkflow < BetterService::Workflows::Base
  with_transaction true  # All database changes wrapped in transaction

  step :create_order, with: Order::CreateService
  step :create_line_items, with: Order::CreateLineItemsService
  step :update_inventory, with: Inventory::DecrementService

  # If any step fails, all database changes are rolled back
end
```

--------------------------------

## Workflow Results

### Result Structure

Workflows return detailed results.

```ruby
result = Order::CheckoutWorkflow.new(user, params: { cart_id: 1 }).call

result[:success]           # => true/false
result[:context]           # => Context object with all step results
result[:metadata]          # => Execution metadata

result[:metadata][:workflow]         # => "Order::CheckoutWorkflow"
result[:metadata][:steps_executed]   # => [:validate_cart, :create_order, ...]
result[:metadata][:branches_taken]   # => ["branch_1:on_1"]
result[:metadata][:duration_ms]      # => 1234.56
```

--------------------------------

### Accessing Step Results

Get results from specific steps.

```ruby
result = OrderWorkflow.new(user, params: params).call

if result[:success]
  order = result[:context].create_order
  payment = result[:context].charge_payment

  render json: { order: order, payment_id: payment.id }
end
```

--------------------------------

## Error Handling

### Workflow Errors

Handle workflow-specific errors.

```ruby
begin
  result = Order::CheckoutWorkflow.new(user, params: params).call
rescue BetterService::Errors::Workflowable::Runtime::StepExecutionError => e
  # A specific step failed
  Rails.logger.error "Step #{e.context[:step]} failed: #{e.message}"
rescue BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError => e
  # General workflow failure
  Rails.logger.error "Workflow failed: #{e.message}"
rescue BetterService::Errors::Workflowable::Runtime::RollbackError => e
  # Rollback itself failed
  Rails.logger.error "Rollback failed: #{e.message}"
  # Manual intervention may be needed
end
```

--------------------------------

## Generating Workflows

### Use the Generator

Generate workflow files quickly.

```bash
rails g serviceable:workflow Order::Checkout
# Creates:
# app/workflows/order/checkout_workflow.rb
# test/workflows/order/checkout_workflow_test.rb

rails g serviceable:workflow Subscription::Renewal
rails g serviceable:workflow User::Onboarding
```

--------------------------------

## Complete Example

### E-commerce Checkout

Full checkout workflow with all features.

```ruby
class Order::CheckoutWorkflow < BetterService::Workflows::Base
  with_transaction true

  # Step 1: Validate cart
  step :validate_cart,
       with: Cart::ValidateService,
       input: ->(ctx) { { cart_id: ctx.cart_id } }

  # Step 2: Check inventory
  step :check_inventory,
       with: Inventory::CheckService,
       input: ->(ctx) { { items: ctx.validate_cart.items } }

  # Step 3: Create order
  step :create_order,
       with: Order::CreateService,
       input: ->(ctx) {
         {
           user: ctx.user,
           items: ctx.validate_cart.items,
           total: ctx.validate_cart.total
         }
       }

  # Step 4: Process payment (branched)
  branch do
    on ->(ctx) { ctx.validate_cart.payment_method == "card" } do
      step :charge_card,
           with: Payment::CardService,
           input: ->(ctx) { { order: ctx.create_order } },
           rollback: ->(ctx) {
             Payment::RefundService.new(ctx.user, params: {
               charge_id: ctx.charge_card.id
             }).call
           }
    end

    on ->(ctx) { ctx.validate_cart.payment_method == "paypal" } do
      step :charge_paypal,
           with: Payment::PaypalService,
           input: ->(ctx) { { order: ctx.create_order } },
           rollback: ->(ctx) {
             Payment::PaypalRefundService.new(ctx.user, params: {
               transaction_id: ctx.charge_paypal.id
             }).call
           }
    end
  end

  # Step 5: Reserve inventory
  step :reserve_inventory,
       with: Inventory::ReserveService,
       input: ->(ctx) { { order: ctx.create_order } },
       rollback: ->(ctx) {
         Inventory::ReleaseService.new(ctx.user, params: {
           reservation_id: ctx.reserve_inventory.id
         }).call
       }

  # Step 6: Clear cart
  step :clear_cart,
       with: Cart::ClearService,
       input: ->(ctx) { { cart_id: ctx.cart_id } }

  # Step 7: Send confirmation (optional)
  step :send_email,
       with: Email::OrderConfirmationService,
       input: ->(ctx) { { order: ctx.create_order } },
       optional: true
end
```

--------------------------------

## Next Steps

### Continue Learning

What to learn next.

```ruby
# Now that you understand workflows:

# 1. Master error handling
#    → guide/07-error-handling.md

# 2. Test your services
#    → guide/08-testing.md
```

--------------------------------
