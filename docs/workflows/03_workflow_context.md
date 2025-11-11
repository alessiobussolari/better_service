# Workflow Context

## Overview

The workflow context is a hash that starts with input parameters and grows as each step adds its results. It's the shared state that flows through the entire workflow.

## How Context Works

### Initial Context

The context starts with the parameters passed to the workflow:

```ruby
workflow = Order::CheckoutWorkflow.new(user, params: {
  cart_id: 123,
  payment_method: 'credit_card',
  coupon_code: 'SAVE20'
})

# Initial context
{
  cart_id: 123,
  payment_method: 'credit_card',
  coupon_code: 'SAVE20'
}
```

### Context Growth

Each step adds its results to the context:

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  step :create_order, with: Order::CreateService
  step :charge_payment, with: Payment::ChargeService
  step :send_confirmation, with: Email::ConfirmationService
end

# After step :create_order
{
  cart_id: 123,
  payment_method: 'credit_card',
  coupon_code: 'SAVE20',
  order: #<Order id: 456, ...>  # Added by CreateService
}

# After step :charge_payment
{
  cart_id: 123,
  payment_method: 'credit_card',
  coupon_code: 'SAVE20',
  order: #<Order id: 456, ...>,
  payment: #<Payment id: 789, ...>  # Added by ChargeService
}

# After step :send_confirmation
{
  cart_id: 123,
  payment_method: 'credit_card',
  coupon_code: 'SAVE20',
  order: #<Order id: 456, ...>,
  payment: #<Payment id: 789, ...>,
  resource: true  # Added by ConfirmationService
}
```

### Final Result

The workflow returns the accumulated context:

```ruby
result = workflow.call

result
# => {
#   cart_id: 123,
#   payment_method: 'credit_card',
#   coupon_code: 'SAVE20',
#   order: #<Order id: 456, ...>,
#   payment: #<Payment id: 789, ...>,
#   resource: true
# }

# Access specific values
result[:order]    # => #<Order id: 456, ...>
result[:payment]  # => #<Payment id: 789, ...>
```

## Context Keys

### Standard Keys

Each service adds specific keys based on its type:

**IndexService** adds `:items`:
```ruby
{
  items: [<Product>, <Product>, ...]
}
```

**ShowService** adds `:resource`:
```ruby
{
  resource: #<Product id: 123, ...>
}
```

**CreateService** adds `:resource`:
```ruby
{
  resource: #<Product id: 456, ...>
}
```

**UpdateService** adds `:resource`:
```ruby
{
  resource: #<Product id: 456, ...>
}
```

**DestroyService** adds `:resource`:
```ruby
{
  resource: #<Product id: 456, ...>  # Destroyed object
}
```

**ActionService** adds custom keys:
```ruby
{
  resource: <varies>,
  # Plus any custom keys from respond_with
}
```

### Custom Keys

Services can add custom keys via `respond_with`:

```ruby
class Order::CreateService < BetterService::CreateService
  respond_with do |data|
    success_result("Order created", data).merge(
      order_number: data[:resource].number,
      total: data[:resource].total,
      items_count: data[:resource].items.count
    )
  end
end

# Context after this service
{
  resource: #<Order>,
  order_number: "ORD-123",
  total: 299.99,
  items_count: 3
}
```

## Accessing Context in Steps

### In Parameter Mapping

```ruby
step :charge_payment,
     with: Payment::ChargeService,
     params: ->(context) {
       {
         # Access values from previous steps
         order_id: context[:order].id,
         amount: context[:order].total,
         payment_method: context[:payment_method]
       }
     }
```

### In Conditions

```ruby
step :apply_discount,
     with: Order::ApplyDiscountService,
     if: ->(context) {
       # Check context values
       context[:coupon_code].present? && context[:order].total > 50
     }
```

### In Error Handlers

```ruby
step :process_payment,
     with: Payment::ProcessService,
     on_error: ->(context, error) {
       # Log with context information
       logger.error "Payment failed",
         order_id: context[:order]&.id,
         user_id: context[:user]&.id,
         error: error.message
     }
```

## Context Patterns

### Pattern 1: Building Complex Objects

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  # Step 1: Create base order
  step :create_order,
       with: Order::CreateService,
       params: ->(context) {
         {
           cart_id: context[:cart_id],
           user_id: context[:user_id]
         }
       }

  # Step 2: Add discount (uses order from step 1)
  step :apply_discount,
       with: Order::ApplyDiscountService,
       if: ->(context) { context[:coupon_code].present? },
       params: ->(context) {
         {
           order_id: context[:order].id,  # From step 1
           coupon_code: context[:coupon_code]
         }
       }

  # Step 3: Calculate shipping (uses updated order)
  step :calculate_shipping,
       with: Order::CalculateShippingService,
       params: ->(context) {
         {
           order_id: context[:order].id,  # From step 1 (updated by step 2)
           address: context[:shipping_address]
         }
       }
end
```

### Pattern 2: Accumulating Results

```ruby
class Report::GenerateWorkflow < BetterService::Workflow
  # Each step adds to the report
  step :fetch_sales_data,
       with: Report::FetchSalesService

  # Uses sales_data from previous step
  step :fetch_user_data,
       with: Report::FetchUsersService

  # Uses both sales_data and user_data
  step :calculate_metrics,
       with: Report::CalculateMetricsService,
       params: ->(context) {
         {
           sales: context[:sales_data],
           users: context[:user_data]
         }
       }

  # Uses everything to generate report
  step :generate_report,
       with: Report::GenerateService,
       params: ->(context) {
         {
           sales: context[:sales_data],
           users: context[:user_data],
           metrics: context[:metrics]
         }
       }
end
```

### Pattern 3: Conditional Data Flow

```ruby
class User::OnboardingWorkflow < BetterService::Workflow
  # Always create user
  step :create_user, with: User::CreateService

  # Conditionally process referral
  step :process_referral,
       with: User::ProcessReferralService,
       if: ->(context) { context[:referral_code].present? },
       params: ->(context) {
         {
           user_id: context[:user].id,
           referral_code: context[:referral_code]
         }
       }

  # Use referral bonus if it was processed
  step :apply_welcome_bonus,
       with: User::ApplyBonusService,
       params: ->(context) {
         bonus_amount = if context[:referral_bonus]
           context[:referral_bonus] + 10  # Extra for referral
         else
           10  # Standard welcome bonus
         end

         {
           user_id: context[:user].id,
           amount: bonus_amount
         }
       }
end
```

### Pattern 4: Passing Through Data

```ruby
class Article::PublishWorkflow < BetterService::Workflow
  schema do
    required(:article_id).filled(:integer)
    optional(:publish_at).maybe(:time)
    optional(:notify_subscribers).maybe(:bool)
  end

  step :publish_article,
       with: Article::PublishService,
       params: ->(context) {
         {
           id: context[:article_id],
           publish_at: context[:publish_at]
         }
       }

  # Pass through original parameter
  step :notify_subscribers,
       with: Article::NotifyService,
       if: ->(context) { context[:notify_subscribers] != false },
       params: ->(context) {
         {
           article_id: context[:article].id
         }
       }
end
```

## Managing Context

### Adding Metadata

Services can add metadata to context:

```ruby
class Order::CreateService < BetterService::CreateService
  respond_with do |data|
    success_result("Order created", data).merge(
      # Add useful metadata to context
      created_at: Time.current,
      processing_time: calculate_processing_time,
      warnings: check_for_warnings(data[:resource])
    )
  end
end

# Workflow can use this metadata
step :send_notification,
     with: Email::NotificationService,
     if: ->(context) { context[:warnings].any? }
```

### Transforming Data

```ruby
class DataProcessingWorkflow < BetterService::Workflow
  step :fetch_raw_data,
       with: Data::FetchService

  step :transform_data,
       with: Data::TransformService,
       params: ->(context) {
         # Transform raw data before passing
         {
           data: context[:raw_data].map { |row|
             {
               id: row[:id],
               value: row[:amount].to_f,
               timestamp: Time.parse(row[:date])
             }
           }
         }
       }
end
```

### Cleaning Up Context

Sometimes you want to remove keys from context:

```ruby
class SecureWorkflow < BetterService::Workflow
  step :authenticate,
       with: Auth::AuthenticateService

  step :process_request,
       with: Request::ProcessService,
       params: ->(context) {
         # Don't pass sensitive data to next service
         context.except(:password, :token, :secret_key)
       }
end
```

## Context in Different Phases

### Validation Phase

Before workflow execution, parameters are validated:

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  schema do
    required(:cart_id).filled(:integer)
    required(:payment_method).filled(:string)
  end

  # If validation fails, workflow never starts
  # Context is never created
end
```

### Execution Phase

During execution, context grows with each step:

```ruby
# Initial
{ cart_id: 1, payment_method: 'card' }

# After step 1
{ cart_id: 1, payment_method: 'card', order: <Order> }

# After step 2
{ cart_id: 1, payment_method: 'card', order: <Order>, payment: <Payment> }
```

### Rollback Phase

If a step fails, context is discarded:

```ruby
# Step 1 succeeds: order created
{ order: <Order> }

# Step 2 succeeds: payment charged
{ order: <Order>, payment: <Payment> }

# Step 3 fails: email service error
# Entire transaction rolls back
# Context is discarded
# Error is raised
```

### Result Phase

On success, final context is returned:

```ruby
result = workflow.call

result[:success]  # => true
result[:order]    # => <Order>
result[:payment]  # => <Payment>
result[:message]  # => "Checkout completed successfully"
```

## Best Practices

### 1. Use Descriptive Keys

```ruby
# ✅ Good: Clear key names
{
  user: <User>,
  order: <Order>,
  payment: <Payment>,
  confirmation_email_sent: true
}

# ❌ Bad: Unclear keys
{
  u: <User>,
  o: <Order>,
  p: <Payment>,
  sent: true
}
```

### 2. Don't Mutate Context Objects

```ruby
# ❌ Bad: Mutating context objects
step :update_order,
     params: ->(context) {
       order = context[:order]
       order.status = 'processing'  # Don't mutate!
       { order_id: order.id }
     }

# ✅ Good: Let services handle mutations
step :update_order,
     with: Order::UpdateStatusService,
     params: ->(context) {
       {
         order_id: context[:order].id,
         status: 'processing'
       }
     }
```

### 3. Keep Context Flat When Possible

```ruby
# ✅ Good: Flat structure
{
  user_id: 123,
  order_id: 456,
  payment_id: 789
}

# ⚠️  Use nesting sparingly
{
  user: {
    id: 123,
    profile: {
      name: "John",
      settings: { ... }
    }
  }
}
```

### 4. Document Expected Context

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  # Expected input parameters:
  # - cart_id: Integer
  # - payment_method: String
  # - shipping_address: Hash
  # - coupon_code: String (optional)
  #
  # Resulting context:
  # - order: Order (from create_order)
  # - payment: Payment (from charge_payment)
  # - confirmation_sent: Boolean (from send_confirmation)

  schema do
    required(:cart_id).filled(:integer)
    required(:payment_method).filled(:string)
    required(:shipping_address).hash
    optional(:coupon_code).maybe(:string)
  end

  step :create_order, with: Order::CreateService
  step :charge_payment, with: Payment::ChargeService
  step :send_confirmation, with: Email::ConfirmationService
end
```

### 5. Validate Context Expectations

```ruby
step :charge_payment,
     with: Payment::ChargeService,
     params: ->(context) {
       # Validate expected keys exist
       raise "Order not found in context" unless context[:order]
       raise "Order must have a total" unless context[:order].total

       {
         order_id: context[:order].id,
         amount: context[:order].total
       }
     }
```

## Debugging Context

### Logging Context

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  step :create_order, with: Order::CreateService

  step :log_context,
       with: DebugService,
       params: ->(context) {
         logger.debug "Context after create_order: #{context.inspect}"
         context
       }

  step :charge_payment, with: Payment::ChargeService
end
```

### Inspecting in Tests

```ruby
RSpec.describe Order::CheckoutWorkflow do
  it 'builds correct context' do
    result = described_class.new(user, params: {
      cart_id: cart.id,
      payment_method: 'credit_card'
    }).call

    # Inspect context
    expect(result).to include(
      cart_id: cart.id,
      payment_method: 'credit_card',
      order: be_a(Order),
      payment: be_a(Payment)
    )

    # Inspect specific values
    expect(result[:order].total).to eq(299.99)
    expect(result[:payment].status).to eq('completed')
  end
end
```

### Using Breakpoints

```ruby
step :debug_step,
     params: ->(context) {
       binding.pry  # Pry breakpoint
       # or
       debugger     # Ruby debugger
       context
     }
```

## Common Pitfalls

### Pitfall 1: Assuming Key Exists

```ruby
# ❌ Bad: May raise NoMethodError
step :use_order,
     params: ->(context) {
       { order_id: context[:order].id }  # What if :order is nil?
     }

# ✅ Good: Check existence
step :use_order,
     params: ->(context) {
       raise "Order not in context" unless context[:order]
       { order_id: context[:order].id }
     }

# ✅ Better: Use safe navigation
step :use_order,
     params: ->(context) {
       { order_id: context[:order]&.id }
     }
```

### Pitfall 2: Context Pollution

```ruby
# ❌ Bad: Adding too many keys
class MyService < BetterService::CreateService
  respond_with do |data|
    success_result("Done", data).merge(
      temp_var_1: ...,
      temp_var_2: ...,
      debug_info: ...,
      internal_state: ...,
      # Too much noise in context!
    )
  end
end

# ✅ Good: Only add useful data
class MyService < BetterService::CreateService
  respond_with do |data|
    success_result("Done", data).merge(
      resource: data[:resource],
      # Only what's needed by next steps
    )
  end
end
```

### Pitfall 3: Overwriting Keys

```ruby
# ❌ Bad: Services might overwrite each other's keys
step :create_user, with: User::CreateService     # Adds :resource
step :create_order, with: Order::CreateService   # Overwrites :resource!

# ✅ Good: Use specific keys
class User::CreateService
  respond_with do |data|
    success_result("User created", data).merge(user: data[:resource])
  end
end

class Order::CreateService
  respond_with do |data|
    success_result("Order created", data).merge(order: data[:resource])
  end
end
```

---

**See also:**
- [Workflows Introduction](01_workflows_introduction.md)
- [Workflow Steps](02_workflow_steps.md)
- [Workflow Lifecycle](04_workflow_lifecycle.md)
- [Workflow Examples](05_workflow_examples.md)
