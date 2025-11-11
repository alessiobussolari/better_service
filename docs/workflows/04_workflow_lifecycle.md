# Workflow Lifecycle

## Overview

A workflow goes through several phases during execution: initialization, validation, authorization, execution, and completion. Understanding this lifecycle helps you build robust workflows.

## Lifecycle Phases

```
1. Initialize  → Create workflow instance
2. Validate    → Check parameters against schema
3. Authorize   → Verify user permissions (if configured)
4. Execute     → Run each step in sequence
5. Complete    → Return final result or raise error
```

## Phase 1: Initialize

### What Happens

```ruby
workflow = Order::CheckoutWorkflow.new(user, params: {
  cart_id: 123,
  payment_method: 'credit_card'
})
```

**Actions:**
1. User object is stored
2. Parameters are stored
3. Workflow instance is created

**No Execution Yet:**
- Schema validation hasn't run
- Authorization hasn't checked
- No steps have executed

---

## Phase 2: Validate

### What Happens

```ruby
result = workflow.call  # Validation happens here
```

**Actions:**
1. Parameters checked against schema
2. Type validations run
3. Custom rules evaluated

**Schema Definition:**

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  schema do
    required(:cart_id).filled(:integer)
    required(:payment_method).filled(:string, included_in?: %w[card paypal])
    optional(:coupon_code).maybe(:string)

    # Custom rules
    rule(:cart_id) do
      if Cart.exists?(key) == false
        key.failure('cart not found')
      end
    end
  end
end
```

**Success Path:**
- Validation passes
- Workflow continues to authorization

**Failure Path:**
```ruby
workflow.call
# => raises BetterService::Errors::Runtime::ValidationError
```

**Error Handling:**

```ruby
begin
  result = Order::CheckoutWorkflow.new(user, params: invalid_params).call
rescue BetterService::Errors::Runtime::ValidationError => e
  # Validation failed
  errors = e.validation_errors
  # {
  #   cart_id: ["must be an integer"],
  #   payment_method: ["must be one of: card, paypal"]
  # }
end
```

---

## Phase 3: Authorize

### What Happens

Authorization runs if `authorize_with` is defined:

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  authorize_with do
    user.active? && !user.banned?
  end

  # Steps...
end
```

**Actions:**
1. Authorization block is executed
2. User is checked
3. Context may be accessed

**Success Path:**
```ruby
# authorize_with returns true
# Workflow continues to execution
```

**Failure Path:**
```ruby
# authorize_with returns false or raises error
# => raises BetterService::Errors::Runtime::AuthorizationError
```

**Example:**

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  authorize_with do
    # Can access user
    return false unless user.present?

    # Can access params
    cart = Cart.find(params[:cart_id])
    cart.user_id == user.id

    # Can perform complex checks
    user.active? && !user.banned? && cart.user_id == user.id
  end
end
```

**Error Handling:**

```ruby
begin
  result = workflow.call
rescue BetterService::Errors::Runtime::AuthorizationError => e
  # User not authorized
  render json: { error: "Access denied" }, status: :forbidden
end
```

---

## Phase 4: Execute

### What Happens

Steps execute sequentially in a transaction:

```ruby
ActiveRecord::Base.transaction do
  step_1_result = execute_step(:step_1)
  context.merge!(step_1_result)

  step_2_result = execute_step(:step_2)
  context.merge!(step_2_result)

  step_3_result = execute_step(:step_3)
  context.merge!(step_3_result)

  # All succeeded - commit
end
```

### Step Execution Flow

For each step:

```
1. Check conditions (if/unless)
   ↓
2. Map parameters from context
   ↓
3. Instantiate service
   ↓
4. Call service
   ↓
5. Merge result into context
   ↓
6. Continue to next step
```

### Example Execution

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  step :create_order, with: Order::CreateService
  step :charge_payment, with: Payment::ChargeService
  step :send_confirmation, with: Email::ConfirmationService
end

# Execution trace:
# 1. Transaction begins
# 2. Execute create_order
#    - Order::CreateService.new(user, params: context).call
#    - Returns { resource: #<Order> }
#    - Context now: { ..., order: #<Order> }
# 3. Execute charge_payment
#    - Payment::ChargeService.new(user, params: context).call
#    - Returns { resource: #<Payment> }
#    - Context now: { ..., order: #<Order>, payment: #<Payment> }
# 4. Execute send_confirmation
#    - Email::ConfirmationService.new(user, params: context).call
#    - Returns { resource: true }
#    - Context now: { ..., order: #<Order>, payment: #<Payment>, resource: true }
# 5. All steps succeeded
# 6. Transaction commits
# 7. Return context
```

### Conditional Execution

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  # Always runs
  step :create_order, with: Order::CreateService

  # Conditionally runs
  step :apply_discount,
       with: Order::ApplyDiscountService,
       if: ->(context) { context[:coupon_code].present? }

  # Always runs
  step :charge_payment, with: Payment::ChargeService
end

# Execution with coupon:
# 1. create_order ✓
# 2. apply_discount ✓ (condition true)
# 3. charge_payment ✓

# Execution without coupon:
# 1. create_order ✓
# 2. apply_discount ⊘ (condition false - skipped)
# 3. charge_payment ✓
```

### Error During Execution

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  step :create_order, with: Order::CreateService
  step :charge_payment, with: Payment::ChargeService  # Fails here
  step :send_confirmation, with: Email::ConfirmationService
end

# Execution trace with error:
# 1. Transaction begins
# 2. create_order executes
#    - Order created (id: 123)
#    - Context: { order: #<Order id: 123> }
# 3. charge_payment executes
#    - Payment fails (card declined)
#    - Error raised: BetterService::Errors::Runtime::ExecutionError
#    - on_error callback runs (if defined)
# 4. Transaction rolls back
#    - Order (id: 123) is deleted
#    - Database back to original state
# 5. send_confirmation never executes
# 6. Error re-raised to caller
```

---

## Phase 5: Complete

### Success Completion

```ruby
result = workflow.call

# Returns merged context
result
# => {
#   success: true,
#   message: "Workflow completed successfully",
#   metadata: { action: :workflow },
#   cart_id: 123,
#   payment_method: 'credit_card',
#   order: #<Order>,
#   payment: #<Payment>,
#   confirmation_sent: true
# }
```

### Failure Completion

```ruby
begin
  result = workflow.call
rescue BetterService::Errors::Runtime::ValidationError => e
  # Validation failed in phase 2
  handle_validation_error(e)
rescue BetterService::Errors::Runtime::AuthorizationError => e
  # Authorization failed in phase 3
  handle_authorization_error(e)
rescue BetterService::Errors::Runtime::ExecutionError => e
  # Step execution failed in phase 4
  handle_execution_error(e)
rescue StandardError => e
  # Unexpected error
  handle_unexpected_error(e)
end
```

---

## Transaction Management

### Automatic Transaction

Workflows wrap all steps in a transaction:

```ruby
# Workflow automatically does this:
ActiveRecord::Base.transaction do
  execute_all_steps
end
```

**Benefits:**
- Automatic rollback on error
- All-or-nothing execution
- Data consistency guaranteed

### Transaction Behavior

```ruby
# Before workflow
Order.count  # => 0
Payment.count  # => 0

# Execute workflow
begin
  Order::CheckoutWorkflow.new(user, params: {
    cart_id: cart.id,
    payment_method: 'card'
  }).call
rescue BetterService::Errors::Runtime::ExecutionError
  # Payment failed
end

# After workflow (with error)
Order.count  # => 0 (rolled back)
Payment.count  # => 0 (rolled back)
```

### Nested Transactions

Services with transactions inside workflow:

```ruby
# Workflow transaction
ActiveRecord::Base.transaction do
  # Step 1
  Order::CreateService.new(user, params: {}).call
  # Service also has transaction - nested

  # Step 2
  Payment::ChargeService.new(user, params: {}).call
  # Service transaction - nested

  # If any fails, all roll back
end
```

**Important:** Nested transactions use savepoints, so rollback is handled correctly.

---

## Error Handling in Lifecycle

### Validation Errors

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  schema do
    required(:cart_id).filled(:integer)
  end
end

# Invalid params
workflow.new(user, params: { cart_id: "invalid" }).call
# => BetterService::Errors::Runtime::ValidationError
# Lifecycle stops at Phase 2
# No steps execute
# No transaction opens
```

### Authorization Errors

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  authorize_with do
    user.admin?  # User is not admin
  end
end

workflow.new(regular_user, params: {}).call
# => BetterService::Errors::Runtime::AuthorizationError
# Lifecycle stops at Phase 3
# No steps execute
# No transaction opens
```

### Execution Errors

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  step :create_order, with: Order::CreateService  # ✓ Succeeds
  step :charge_payment, with: Payment::ChargeService  # ✗ Fails
  step :send_email, with: Email::ConfirmationService  # Never runs
end

workflow.new(user, params: {}).call
# Step 1 executes
# Step 2 fails
# => BetterService::Errors::Runtime::ExecutionError
# Transaction rolls back
# Step 3 never executes
```

### Custom Error Handling

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  step :charge_payment,
       with: Payment::ChargeService,
       on_error: ->(context, error) {
         # Log error
         PaymentLogger.log_failure(context[:order], error)

         # Notify admin
         AdminMailer.payment_failed(context[:order]).deliver_later

         # Track metric
         Metrics.increment('payment.failures')

         # Error still bubbles up and causes rollback
       }
end
```

---

## Lifecycle Hooks

### Before Execution

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  def before_execution
    # Called after validation and authorization
    # Before first step executes
    logger.info "Starting checkout for user #{user.id}"
  end

  step :create_order, with: Order::CreateService
  # ...
end
```

### After Execution

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  step :create_order, with: Order::CreateService
  # ...

  def after_execution(result)
    # Called after all steps succeed
    # Before result is returned
    logger.info "Checkout completed for order #{result[:order].id}"

    # Track analytics
    Analytics.track('checkout_completed', {
      user_id: user.id,
      order_id: result[:order].id,
      total: result[:order].total
    })
  end
end
```

### On Error

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  def on_workflow_error(error)
    # Called when any step fails
    # After transaction rollback
    # Before error is re-raised

    logger.error "Workflow failed: #{error.message}"

    # Send notification
    ErrorNotifier.notify(error, {
      workflow: self.class.name,
      user_id: user.id,
      params: params
    })
  end
end
```

---

## Complete Lifecycle Example

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  # Configuration
  schema do
    required(:cart_id).filled(:integer)
    required(:payment_method).filled(:string)
  end

  authorize_with do
    user.active? && !user.banned?
  end

  # Hooks
  def before_execution
    logger.info "Checkout starting for user #{user.id}"
    Metrics.increment('checkout.started')
  end

  def after_execution(result)
    logger.info "Checkout completed: order #{result[:order].id}"
    Metrics.increment('checkout.completed')
    Analytics.track('checkout_completed', {
      user_id: user.id,
      order_id: result[:order].id
    })
  end

  def on_workflow_error(error)
    logger.error "Checkout failed: #{error.message}"
    Metrics.increment('checkout.failed')
  end

  # Steps
  step :create_order, with: Order::CreateService

  step :apply_discount,
       with: Order::ApplyDiscountService,
       if: ->(context) { context[:coupon_code].present? }

  step :charge_payment,
       with: Payment::ChargeService,
       on_error: ->(context, error) {
         PaymentLogger.log_failure(context[:order], error)
       }

  step :confirm_order, with: Order::ConfirmService

  step :send_confirmation, with: Email::ConfirmationService
end

# Usage
workflow = Order::CheckoutWorkflow.new(user, params: {
  cart_id: 123,
  payment_method: 'credit_card',
  coupon_code: 'SAVE20'
})

# Execution trace:
# 1. Initialize ✓
# 2. Validate ✓
# 3. Authorize ✓
# 4. before_execution ✓
# 5. Transaction begins
# 6. create_order ✓
# 7. apply_discount ✓ (condition met)
# 8. charge_payment ✓
# 9. confirm_order ✓
# 10. send_confirmation ✓
# 11. Transaction commits
# 12. after_execution ✓
# 13. Return result

result = workflow.call
```

---

## Best Practices

### 1. Keep Workflows Focused

```ruby
# ✅ Good: Single responsibility
class Order::CheckoutWorkflow
  # Handles checkout only
end

class Order::FulfillmentWorkflow
  # Handles fulfillment separately
end

# ❌ Bad: Too many responsibilities
class Order::EverythingWorkflow
  # Checkout, fulfillment, shipping, returns, etc.
end
```

### 2. Use Hooks Wisely

```ruby
# ✅ Good: Light logging and metrics
def after_execution(result)
  logger.info "Completed"
  Metrics.increment('completed')
end

# ❌ Bad: Heavy processing in hooks
def after_execution(result)
  # Don't do heavy work here
  GenerateInvoice.new(result[:order]).call
  SendToWarehouse.new(result[:order]).call
  UpdateInventory.new(result[:order]).call
  # Use workflow steps instead!
end
```

### 3. Handle Errors Appropriately

```ruby
# ✅ Good: Log and let error bubble
step :critical_step,
     with: CriticalService,
     on_error: ->(context, error) {
       logger.error "Critical step failed: #{error.message}"
       # Error still bubbles up - workflow fails
     }

# ❌ Bad: Swallowing errors
step :important_step,
     with: ImportantService,
     on_error: ->(context, error) {
       # Don't try to suppress the error
       # It will bubble up anyway
     }
```

### 4. Test the Entire Lifecycle

```ruby
RSpec.describe Order::CheckoutWorkflow do
  # Test happy path
  it 'completes successfully' do
    result = described_class.new(user, params: valid_params).call
    expect(result[:success]).to be true
  end

  # Test validation
  it 'fails with invalid params' do
    expect {
      described_class.new(user, params: {}).call
    }.to raise_error(BetterService::Errors::Runtime::ValidationError)
  end

  # Test authorization
  it 'fails for unauthorized users' do
    expect {
      described_class.new(banned_user, params: valid_params).call
    }.to raise_error(BetterService::Errors::Runtime::AuthorizationError)
  end

  # Test rollback
  it 'rolls back on payment failure' do
    allow(Payment::ChargeService).to receive(:new).and_raise(PaymentError)

    expect {
      described_class.new(user, params: valid_params).call rescue nil
    }.not_to change(Order, :count)
  end
end
```

---

**See also:**
- [Workflows Introduction](01_workflows_introduction.md)
- [Workflow Steps](02_workflow_steps.md)
- [Workflow Context](03_workflow_context.md)
- [Workflow Examples](05_workflow_examples.md)
