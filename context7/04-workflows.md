# Workflows

Workflows orchestrate multiple services with automatic rollback and conditional branching.

---

## Basic Workflow

### Linear Workflow

Sequential execution of multiple services.

```ruby
class Order::CheckoutWorkflow < BetterService::Workflows::Base
  with_transaction true

  step :validate_cart,
       with: Cart::ValidateService,
       input: ->(ctx) { { cart_id: ctx.cart_id } }

  step :charge_payment,
       with: Payment::ChargeService,
       input: ->(ctx) { { amount: ctx.validate_cart.total } },
       rollback: ->(ctx) { Payment::RefundService.new(ctx.user, params: { charge_id: ctx.charge_payment.id }).call }

  step :create_order,
       with: Order::CreateService,
       input: ->(ctx) { { cart: ctx.validate_cart, charge: ctx.charge_payment } }

  step :send_email,
       with: Email::ConfirmationService,
       input: ->(ctx) { { order: ctx.create_order } },
       optional: true

  step :clear_cart,
       with: Cart::ClearService,
       input: ->(ctx) { { cart_id: ctx.cart_id } }
end

# Usage
result = Order::CheckoutWorkflow.new(current_user, params: { cart_id: 123 }).call
```

--------------------------------

## Step Options

### Available Step Options

Configuration options for workflow steps.

```ruby
# Option      | Type    | Description
# ------------|---------|----------------------------------
# with:       | Class   | Service class to execute (required)
# input:      | Lambda  | Map context to service params
# rollback:   | Lambda  | Undo logic if later step fails
# optional:   | Boolean | Continue on failure (default: false)
# if:         | Lambda  | Conditional execution
```

--------------------------------

### Input Mapping

Map context data to service parameters.

```ruby
step :create_order,
     with: Order::CreateService,
     input: ->(ctx) {
       {
         cart_id: ctx.cart_id,           # From workflow params
         total: ctx.validate_cart.total, # From previous step
         payment_id: ctx.charge_payment.id
       }
     }
```

--------------------------------

### Rollback Handler

Define rollback logic for when subsequent steps fail.

```ruby
step :charge_payment,
     with: Payment::ChargeService,
     rollback: ->(ctx) {
       # Called if any subsequent step fails
       Payment::RefundService.new(
         ctx.user,
         params: { charge_id: ctx.charge_payment.id }
       ).call
     }
```

--------------------------------

### Optional Steps

Mark steps as optional to continue on failure.

```ruby
step :send_notification,
     with: Notification::SendService,
     optional: true  # Workflow continues even if this fails
```

--------------------------------

### Conditional Steps

Execute steps based on runtime conditions.

```ruby
step :apply_discount,
     with: Discount::ApplyService,
     if: ->(ctx) { ctx.validate_cart.has_coupon? }
```

--------------------------------

## Conditional Branching

### Branch Syntax

Execute different paths based on conditions.

```ruby
class Order::ProcessPaymentWorkflow < BetterService::Workflows::Base
  with_transaction true

  step :validate_order,
       with: Order::ValidateService,
       input: ->(ctx) { { order_id: ctx.order_id } }

  # Branch based on payment method
  branch do
    on ->(ctx) { ctx.validate_order.payment_method == "credit_card" } do
      step :charge_stripe,
           with: Payment::Stripe::ChargeService,
           input: ->(ctx) { { order: ctx.validate_order } }

      step :verify_3d_secure,
           with: Payment::Stripe::Verify3DService,
           input: ->(ctx) { { charge: ctx.charge_stripe } },
           optional: true
    end

    on ->(ctx) { ctx.validate_order.payment_method == "paypal" } do
      step :create_paypal_order,
           with: Payment::Paypal::CreateOrderService,
           input: ->(ctx) { { order: ctx.validate_order } }

      step :capture_paypal,
           with: Payment::Paypal::CaptureService,
           input: ->(ctx) { { paypal_order: ctx.create_paypal_order } }
    end

    on ->(ctx) { ctx.validate_order.payment_method == "bank_transfer" } do
      step :generate_reference,
           with: Payment::BankTransfer::GenerateReferenceService,
           input: ->(ctx) { { order: ctx.validate_order } }
    end

    otherwise do
      step :log_unsupported,
           with: Logging::UnsupportedPaymentService,
           input: ->(ctx) { { order: ctx.validate_order } }
    end
  end

  # Steps after branch execute regardless of which path was taken
  step :update_status,
       with: Order::UpdateStatusService,
       input: ->(ctx) { { order_id: ctx.validate_order.id, status: "processing" } }
end
```

--------------------------------

## Branch Rules

### Branch Execution Rules

How conditional branching works.

```ruby
# 1. First-match wins - Conditions evaluated in order
# 2. Single path - Only one branch executes per block
# 3. Otherwise optional - But error raised if no condition matches and no otherwise
# 4. Nested branches - Branches can contain other branch blocks
# 5. Rollback awareness - Only executed branch steps are rolled back
```

--------------------------------

## Nested Branches

### Complex Decision Trees

Nested branches for complex conditional logic.

```ruby
class Document::ApprovalWorkflow < BetterService::Workflows::Base
  step :validate_document,
       with: Document::ValidateService

  branch do
    on ->(ctx) { ctx.validate_document.type == "contract" } do
      step :legal_review,
           with: Legal::ReviewService

      # Nested branch based on contract value
      branch do
        on ->(ctx) { ctx.validate_document.value > 100_000 } do
          step :ceo_approval,
               with: Approval::CEOService

          step :board_approval,
               with: Approval::BoardService
        end

        on ->(ctx) { ctx.validate_document.value > 10_000 } do
          step :manager_approval,
               with: Approval::ManagerService
        end

        otherwise do
          step :supervisor_approval,
               with: Approval::SupervisorService
        end
      end
    end

    otherwise do
      step :standard_approval,
           with: Approval::StandardService
    end
  end

  step :finalize,
       with: Document::FinalizeService
end
```

--------------------------------

## Context Object

### Working with Context

The context shares data between steps.

```ruby
# Automatic step result storage
ctx.step_name           # Result from step :step_name
ctx.validate_cart       # Result from step :validate_cart
ctx.charge_payment.id   # Access nested data

# Built-in properties
ctx.user               # Workflow user
ctx.params             # Workflow params (ctx.cart_id from params[:cart_id])

# Manual storage
ctx.custom_data = { key: "value" }
ctx.add(:another_key, some_value)
ctx.get(:another_key)
```

--------------------------------

## Workflow Result

### Result Structure

Structure of workflow execution result.

```ruby
result = Order::CheckoutWorkflow.new(user, params: { cart_id: 123 }).call

result[:success]        # => true/false
result[:context]        # => Context object with all step results
result[:metadata]       # => {
                        #      workflow: "Order::CheckoutWorkflow",
                        #      steps_executed: [:validate_cart, :charge_payment, :create_order],
                        #      branches_taken: [],
                        #      duration_ms: 1234.56
                        #    }

# With branching
result[:metadata][:branches_taken]
# => ["branch_1:on_1"]  # First branch, first condition matched

# Nested branches
# => ["branch_1:on_1", "nested_branch_1:on_2"]
```

--------------------------------

## Lifecycle Callbacks

### Before and After Hooks

Execute code before and after workflow execution.

```ruby
class Order::CheckoutWorkflow < BetterService::Workflows::Base
  before_workflow do |context|
    Rails.logger.info "Starting checkout for user #{context.user.id}"
  end

  after_workflow do |context, result|
    if result[:success]
      Analytics.track("checkout_completed", user_id: context.user.id)
    end
  end

  # Steps...
end
```

--------------------------------

## Error Handling

### Handling Workflow Errors

Handle step failures and rollback errors.

```ruby
begin
  result = Order::CheckoutWorkflow.new(user, params: params).call
rescue BetterService::Errors::Workflowable::Runtime::StepExecutionError => e
  Rails.logger.error "Step #{e.context[:step]} failed: #{e.message}"
rescue BetterService::Errors::Workflowable::Runtime::RollbackError => e
  Rails.logger.error "Rollback failed for step #{e.context[:step]}: #{e.message}"
rescue BetterService::Errors::Configuration::InvalidConfigurationError => e
  Rails.logger.error "Workflow misconfigured: #{e.message}"
end
```

--------------------------------

## Complete Example

### Subscription Renewal Workflow

Full workflow example with branching and rollback.

```ruby
class Subscription::RenewWorkflow < BetterService::Workflows::Base
  with_transaction true

  step :load_subscription,
       with: Subscription::LoadService,
       input: ->(ctx) { { id: ctx.subscription_id } }

  step :check_eligibility,
       with: Subscription::CheckEligibilityService,
       input: ->(ctx) { { subscription: ctx.load_subscription } }

  branch do
    on ->(ctx) { ctx.check_eligibility.auto_renew_enabled? } do
      step :charge_stored_payment,
           with: Payment::ChargeStoredMethodService,
           input: ->(ctx) { { subscription: ctx.load_subscription } },
           rollback: ->(ctx) { Payment::RefundService.new(ctx.user, params: { id: ctx.charge_stored_payment.id }).call }
    end

    on ->(ctx) { ctx.check_eligibility.has_credits? } do
      step :apply_credits,
           with: Credits::ApplyService,
           input: ->(ctx) { { subscription: ctx.load_subscription } }
    end

    otherwise do
      step :send_renewal_reminder,
           with: Email::RenewalReminderService,
           input: ->(ctx) { { subscription: ctx.load_subscription } }

      step :mark_pending,
           with: Subscription::MarkPendingService,
           input: ->(ctx) { { subscription: ctx.load_subscription } }
    end
  end

  step :extend_subscription,
       with: Subscription::ExtendService,
       input: ->(ctx) { { subscription: ctx.load_subscription } },
       if: ->(ctx) { ctx.charge_stored_payment || ctx.apply_credits }

  step :send_confirmation,
       with: Email::SubscriptionConfirmationService,
       input: ->(ctx) { { subscription: ctx.load_subscription } },
       optional: true
end
```

--------------------------------
