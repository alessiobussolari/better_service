# Workflows Introduction

## Overview

Workflows orchestrate multiple services into cohesive business processes with automatic transaction management, rollback support, and step-by-step execution.

## What is a Workflow?

A workflow is a sequence of services executed in order to accomplish a complex business operation. If any step fails, all previous steps are automatically rolled back.

**Think of it like:**
- A recipe with multiple steps
- An assembly line where each station does one job
- A chain where every link must hold

## When to Use Workflows

### Use Workflows When:

1. **Multiple Services Must Coordinate**
   ```ruby
   # Order checkout requires multiple services
   - Validate cart
   - Apply discount
   - Charge payment
   - Confirm order
   - Send email
   ```

2. **Rollback is Critical**
   ```ruby
   # If payment fails, order shouldn't be created
   # If email fails, we need to know
   ```

3. **Steps Have Dependencies**
   ```ruby
   # Can't charge payment until order is created
   # Can't send confirmation until payment succeeds
   ```

4. **Process Needs to be Testable**
   ```ruby
   # Test entire checkout flow
   # Test individual steps
   # Test rollback scenarios
   ```

### Don't Use Workflows When:

1. **Single Service Is Enough**
   ```ruby
   # ❌ Don't need workflow
   UpdateProductPriceWorkflow
     step :update_price, with: Product::UpdateService

   # ✅ Just use the service
   Product::UpdateService.new(user, params: { id: 1, price: 99 }).call
   ```

2. **Steps Are Independent**
   ```ruby
   # ❌ Don't need workflow
   # These can run independently
   step :send_email
   step :post_to_slack
   step :update_analytics

   # ✅ Call services independently
   EmailService.new(user, params: {}).call
   SlackService.new(user, params: {}).call
   ```

3. **No Rollback Needed**
   ```ruby
   # If steps can't be rolled back, workflow won't help
   # Example: Sending emails can't be unsent
   ```

## Basic Example

### The Problem

Order checkout requires:
1. Validate cart has items
2. Create order from cart
3. Apply coupon (if provided)
4. Charge payment
5. Confirm order
6. Clear cart
7. Send confirmation email

**Without Workflow (messy):**

```ruby
class OrdersController < ApplicationController
  def create
    # Manually coordinate services
    cart = Cart.find(params[:cart_id])

    begin
      # Service 1
      order = Order::CreateService.new(current_user, params: {
        cart_id: cart.id
      }).call[:resource]

      # Service 2
      if params[:coupon_code]
        Order::ApplyCouponService.new(current_user, params: {
          order_id: order.id,
          code: params[:coupon_code]
        }).call
        order.reload
      end

      # Service 3
      payment = Payment::ChargeService.new(current_user, params: {
        order_id: order.id,
        amount: order.total
      }).call[:resource]

      # Service 4
      Order::ConfirmService.new(current_user, params: {
        order_id: order.id
      }).call

      # Service 5
      Cart::ClearService.new(current_user, params: {
        cart_id: cart.id
      }).call

      # Service 6
      Email::ConfirmationService.new(current_user, params: {
        order_id: order.id
      }).call

      redirect_to order_path(order)
    rescue => e
      # Manual rollback?
      order&.destroy
      flash[:error] = e.message
      redirect_to cart_path
    end
  end
end
```

**With Workflow (clean):**

```ruby
# app/workflows/order/checkout_workflow.rb
module Order
  class CheckoutWorkflow < BetterService::Workflow
    schema do
      required(:cart_id).filled(:integer)
      required(:payment_method).filled(:string)
      optional(:coupon_code).maybe(:string)
    end

    step :create_order, with: Order::CreateService
    step :apply_coupon,
         with: Order::ApplyCouponService,
         if: ->(context) { context[:coupon_code].present? }
    step :charge_payment, with: Payment::ChargeService
    step :confirm_order, with: Order::ConfirmService
    step :clear_cart, with: Cart::ClearService
    step :send_confirmation, with: Email::ConfirmationService
  end
end

# app/controllers/orders_controller.rb
class OrdersController < ApplicationController
  def create
    result = Order::CheckoutWorkflow.new(current_user, params: checkout_params).call

    redirect_to order_path(result[:order])
  rescue BetterService::Errors::Runtime::ExecutionError => e
    flash[:error] = e.message
    redirect_to cart_path
  end
end
```

## How Workflows Work

### 1. Sequential Execution

Steps run in the order defined:

```ruby
class MyWorkflow < BetterService::Workflow
  step :first, with: FirstService      # Runs first
  step :second, with: SecondService    # Then this
  step :third, with: ThirdService      # Then this
end
```

### 2. Context Accumulation

Each step adds to the context:

```ruby
# Initial context
{ user_id: 123 }

# After FirstService (adds :user)
{ user_id: 123, user: #<User> }

# After SecondService (adds :order)
{ user_id: 123, user: #<User>, order: #<Order> }

# After ThirdService (adds :payment)
{ user_id: 123, user: #<User>, order: #<Order>, payment: #<Payment> }
```

### 3. Automatic Rollback

If any step fails, previous steps are rolled back:

```ruby
step :create_order      # ✅ Creates order (ID: 123)
step :charge_payment    # ❌ Payment fails!
# Workflow automatically destroys order (ID: 123)
# Raises error to caller
```

### 4. Transaction Wrapping

Everything runs in a database transaction:

```ruby
ActiveRecord::Base.transaction do
  FirstService.new(user, params: ...).call
  SecondService.new(user, params: ...).call
  ThirdService.new(user, params: ...).call
  # If anything fails, ROLLBACK
  # If all succeed, COMMIT
end
```

## Conditional Branching

### Overview

Workflows support **conditional branching** - executing different steps based on runtime conditions. This enables workflows to handle multiple execution paths without creating separate workflow classes.

**Think of it like:**
- A decision tree where you choose a path
- A "choose your own adventure" for business logic
- A switch statement for workflow execution

### Basic Branch Example

```ruby
class Order::ProcessPaymentWorkflow < BetterService::Workflow
  step :validate_order, with: Order::ValidateService

  # Branch based on payment method
  branch do
    on ->(ctx) { ctx.validate_order.payment_method == 'credit_card' } do
      step :charge_credit_card, with: Payment::ChargeCreditCardService
      step :verify_3d_secure, with: Payment::Verify3DSecureService
    end

    on ->(ctx) { ctx.validate_order.payment_method == 'paypal' } do
      step :charge_paypal, with: Payment::ChargePayPalService
    end

    on ->(ctx) { ctx.validate_order.payment_method == 'bank_transfer' } do
      step :generate_reference, with: Payment::GenerateReferenceService
      step :send_instructions, with: Email::BankInstructionsService
    end

    otherwise do
      step :manual_review, with: Payment::ManualReviewService
    end
  end

  step :finalize_order, with: Order::FinalizeService
end
```

### How Branching Works

**1. Branch Declaration**

Define a branch block with `branch do ... end`:

```ruby
branch do
  # Conditional paths go here
end
```

**2. Conditional Paths**

Use `on` blocks to define conditions:

```ruby
on ->(ctx) { condition } do
  step :some_step, with: SomeService
end
```

**3. Default Path**

Use `otherwise` for the default path:

```ruby
otherwise do
  step :default_step, with: DefaultService
end
```

**4. Execution Rules**

- **First-match wins**: Conditions evaluated in order, first true executes
- **Single path**: Only one branch executes per branch block
- **Otherwise is optional**: But without it, error raised if no condition matches
- **Access to context**: Conditions receive full workflow context

### Branch Execution Example

```ruby
# User is premium
context = { user: #<User premium: true> }

branch do
  on ->(ctx) { ctx.user.premium? } do     # ✅ This executes
    step :premium_feature
  end

  on ->(ctx) { ctx.user.free? } do        # ⏭️ Skipped (first match won)
    step :free_feature
  end

  otherwise do                             # ⏭️ Skipped (match found)
    step :default_feature
  end
end
```

### Nested Branches

Branches can contain other branches for complex decision trees:

```ruby
class Document::ApprovalWorkflow < BetterService::Workflow
  step :validate_document, with: Document::ValidateService

  branch do
    on ->(ctx) { ctx.validate_document.type == 'contract' } do
      step :legal_review, with: Legal::ReviewService

      # Nested branch based on contract value
      branch do
        on ->(ctx) { ctx.validate_document.value > 100_000 } do
          step :ceo_approval, with: Approval::CEOService
        end

        on ->(ctx) { ctx.validate_document.value > 10_000 } do
          step :manager_approval, with: Approval::ManagerService
        end

        otherwise do
          step :supervisor_approval, with: Approval::SupervisorService
        end
      end
    end

    on ->(ctx) { ctx.validate_document.type == 'invoice' } do
      step :finance_approval, with: Approval::FinanceService
    end

    otherwise do
      step :standard_approval, with: Approval::StandardService
    end
  end

  step :finalize_document, with: Document::FinalizeService
end
```

### Branch Metadata

Workflow results include `branches_taken` metadata showing which branches executed:

```ruby
result = Order::ProcessPaymentWorkflow.new(user, params: { ... }).call

result[:metadata]
# => {
#   workflow: "Order::ProcessPaymentWorkflow",
#   steps_executed: [:validate_order, :charge_credit_card, :verify_3d_secure, :finalize_order],
#   branches_taken: ["branch_1:on_1"],  # First branch, first condition
#   duration_ms: 1234.56
# }
```

For nested branches:

```ruby
result[:metadata][:branches_taken]
# => ["branch_1:on_1", "nested_branch_1:on_2"]
# First branch took first condition, nested branch took second condition
```

### Branch Rollback

When a step fails in a branch:
- **Only executed steps are rolled back** (not skipped or non-executed branch steps)
- **Rollback executes in reverse order**
- **Database transaction rolls back** all changes

```ruby
branch do
  on ->(ctx) { ctx.payment_method == 'credit_card' } do
    step :charge_card     # ✅ Executed
    step :verify_3d       # ❌ FAILS
    # Only these two steps rolled back
  end

  on ->(ctx) { ctx.payment_method == 'paypal' } do
    step :charge_paypal   # ⏭️ Never executed, won't be rolled back
  end
end
```

### When to Use Branching

**Use branching when:**
- Different execution paths based on runtime data
- Payment method routing (credit card vs PayPal vs bank transfer)
- User tier features (free vs premium vs enterprise)
- Content type processing (video vs image vs document)
- Approval workflows (different approvers based on amount/type)

**Don't use branching when:**
- Simple conditional steps with `if` are enough
- Only 1-2 conditional steps needed
- Branches would have exactly the same steps

### Branching vs Conditional Steps

```ruby
# ❌ DON'T use branching for simple conditions
branch do
  on ->(ctx) { ctx.coupon_code.present? } do
    step :apply_coupon, with: ApplyCouponService
  end
end

# ✅ DO use conditional step instead
step :apply_coupon,
     with: ApplyCouponService,
     if: ->(ctx) { ctx.coupon_code.present? }

# ✅ DO use branching for multiple different paths
branch do
  on ->(ctx) { ctx.payment_method == 'credit_card' } do
    step :charge_card
    step :verify_3d
    step :store_card
  end

  on ->(ctx) { ctx.payment_method == 'paypal' } do
    step :create_paypal_order
    step :capture_payment
  end

  otherwise do
    step :manual_processing
  end
end
```

---

## Workflow Anatomy

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  # 1. Schema - Validate input parameters
  schema do
    required(:cart_id).filled(:integer)
    required(:payment_method).filled(:string)
  end

  # 2. Steps - Define execution sequence
  step :create_order,
       with: Order::CreateService,              # Service to execute
       params: ->(context) {                    # Map context to params
         { cart_id: context[:cart_id] }
       }

  step :charge_payment,
       with: Payment::ChargeService,
       if: ->(context) { context[:amount] > 0 }, # Conditional execution
       params: ->(context) {
         {
           order_id: context[:order].id,
           amount: context[:order].total
         }
       }

  step :send_confirmation,
       with: Email::ConfirmationService,
       params: ->(context) {
         { order_id: context[:order].id }
       }
end
```

## Key Concepts

### Context

The workflow context is a hash that:
- Starts with workflow parameters
- Grows as each step adds results
- Is passed to conditional checks
- Maps to service parameters

```ruby
# Start
context = { cart_id: 1, payment_method: 'card' }

# After create_order step
context = {
  cart_id: 1,
  payment_method: 'card',
  order: #<Order id: 123>  # Added by CreateService
}

# After charge_payment step
context = {
  cart_id: 1,
  payment_method: 'card',
  order: #<Order id: 123>,
  payment: #<Payment id: 456>  # Added by ChargeService
}
```

### Steps

Steps are service invocations with options:

```ruby
step :step_name,                      # Name (for debugging)
     with: ServiceClass,              # Service to run (required)
     params: ->(context) { {} },      # Parameter mapping
     if: ->(context) { true },        # Conditional execution
     unless: ->(context) { false },   # Inverse conditional
     on_error: ->(context, err) { }   # Error callback
```

### Rollback

When a step fails:
1. Exception is caught
2. Database transaction rolls back
3. All changes are undone
4. Exception is re-raised

```ruby
# Executed
step :create_order        # ✅ Order created
step :apply_discount      # ✅ Discount applied
step :charge_payment      # ❌ FAILS - card declined

# Automatic rollback
# - Payment attempt is rolled back
# - Discount is rolled back
# - Order creation is rolled back
# - Database is back to original state

# Exception raised to caller
raise BetterService::Errors::Runtime::ExecutionError("Payment failed")
```

## Workflow vs Service Composition

### ❌ Anti-Pattern: Service Calling Service

**NEVER DO THIS:**

```ruby
# ❌ WRONG - Don't call services from within services
class Order::CreateService < BetterService::CreateService
  process_with do |data|
    order = Order.create!(params)

    # ❌ WRONG: This creates problems
    Payment::ChargeService.new(user, params: {
      order_id: order.id
    }).call

    { resource: order }
  end
end
```

**Why this is wrong:**
- ❌ No automatic rollback if payment fails
- ❌ Order already persisted in database
- ❌ Hard to test individual steps
- ❌ Tight coupling between services
- ❌ No transaction management across services
- ❌ Difficult to add steps in the middle
- ❌ Can't conditionally execute steps

### ✅ Correct Approach: Use Workflows

**ALWAYS use workflows for multi-service operations:**

```ruby
# ✅ CORRECT - Use workflows to compose services
class Order::CheckoutWorkflow < BetterService::Workflow
  step :create_order, with: Order::CreateService
  step :charge_payment, with: Payment::ChargeService
end
```

**Benefits:**
- ✅ Automatic rollback on any failure
- ✅ Easy to test each step independently
- ✅ Loose coupling between services
- ✅ Clear dependencies and execution order
- ✅ Transaction management across all steps
- ✅ Can add/remove steps easily
- ✅ Supports conditional step execution

**Rule: ALWAYS use workflows for:**
- **Any multi-service operation** (2+ services)
- **Operations that need rollback**
- **Complex business processes**
- **Any operation where order matters**

## Benefits

### 1. Automatic Rollback

```ruby
# All or nothing - no partial state
step :create_order      # Creates order
step :charge_payment    # Fails
# Order is automatically destroyed
```

### 2. Clear Business Process

```ruby
# Reading the workflow = understanding the process
step :validate_cart
step :create_order
step :apply_discount
step :charge_payment
step :confirm_order
```

### 3. Easy Testing

```ruby
# Test entire workflow
it 'completes checkout'

# Test individual steps
it 'creates order'
it 'charges payment'

# Test rollback
it 'rolls back on payment failure'
```

### 4. Conditional Logic

```ruby
# Only execute some steps
step :apply_discount, if: ->(ctx) { ctx[:coupon_code].present? }
step :send_gift_message, if: ->(ctx) { ctx[:is_gift] }
```

### 5. Reusable Steps

```ruby
# Same service in multiple workflows
class Order::CheckoutWorkflow
  step :send_email, with: Email::OrderConfirmationService
end

class Order::RefundWorkflow
  step :send_email, with: Email::RefundConfirmationService
end
```

## Real-World Examples

### E-Commerce Checkout

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  step :validate_cart, with: Cart::ValidateService
  step :create_order, with: Order::CreateService
  step :apply_coupon, with: Order::ApplyCouponService, if: :has_coupon?
  step :calculate_shipping, with: Order::CalculateShippingService
  step :charge_payment, with: Payment::ChargeService
  step :confirm_order, with: Order::ConfirmService
  step :clear_cart, with: Cart::ClearService
  step :send_confirmation, with: Email::ConfirmationService
  step :send_receipt, with: Email::ReceiptService
end
```

### User Onboarding

```ruby
class User::OnboardingWorkflow < BetterService::Workflow
  step :create_account, with: User::CreateService
  step :create_profile, with: Profile::CreateService
  step :setup_preferences, with: Preferences::CreateService
  step :send_welcome_email, with: Email::WelcomeService
  step :send_verification, with: Email::VerificationService
  step :create_sample_data, with: SampleData::CreateService
end
```

### Content Publishing

```ruby
class Article::PublishWorkflow < BetterService::Workflow
  step :validate_content, with: Article::ValidateService
  step :generate_seo, with: Article::GenerateSEOService
  step :optimize_images, with: Article::OptimizeImagesService
  step :publish_article, with: Article::PublishService
  step :index_search, with: Article::IndexSearchService
  step :notify_subscribers, with: Article::NotifySubscribersService
  step :post_to_social, with: Article::PostToSocialService, if: :share_on_social?
end
```

## Next Steps

- **Workflow Steps**: [Learn about step configuration](02_workflow_steps.md)
- **Workflow Context**: [Understanding context management](03_workflow_context.md)
- **Workflow Lifecycle**: [Execution flow and hooks](04_workflow_lifecycle.md)
- **Workflow Examples**: [Real-world patterns](05_workflow_examples.md)

---

**See also:**
- [Services Structure](../services/01_services_structure.md)
- [Workflow Generator](../generators/03_workflow_generator.md)
- [Advanced Workflows](../advanced/workflows.md)
