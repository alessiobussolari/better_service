# Workflow Steps

## Overview

Steps are the building blocks of workflows. Each step executes a service and can be configured with parameters, conditions, and error handling.

## Basic Step Definition

```ruby
class MyWorkflow < BetterService::Workflow
  step :step_name, with: ServiceClass
end
```

## Step Options

### with (Required)

Specifies the service class to execute.

```ruby
step :create_order, with: Order::CreateService
step :charge_payment, with: Payment::ChargeService
step :send_email, with: Email::ConfirmationService
```

**Requirements:**
- Must be a BetterService service class
- Service will be instantiated with current user and mapped parameters

---

### params

Maps workflow context to service parameters.

```ruby
step :step_name,
     with: ServiceClass,
     params: ->(context) {
       {
         param1: context[:value1],
         param2: context[:value2]
       }
     }
```

**Examples:**

```ruby
# Simple mapping
step :create_order,
     with: Order::CreateService,
     params: ->(context) {
       {
         cart_id: context[:cart_id],
         shipping_address: context[:shipping_address]
       }
     }

# Computed values
step :charge_payment,
     with: Payment::ChargeService,
     params: ->(context) {
       {
         order_id: context[:order].id,
         amount: context[:order].total,
         currency: context[:order].currency || 'USD'
       }
     }

# Conditional parameters
step :send_notification,
     with: Email::NotificationService,
     params: ->(context) {
       params = { user_id: context[:user].id }
       params[:cc] = context[:cc_emails] if context[:cc_emails].present?
       params
     }
```

**Default Behavior:**

If `params` is not specified, the entire context is passed:

```ruby
# Without params mapping
step :create_order, with: Order::CreateService
# Equivalent to:
step :create_order,
     with: Order::CreateService,
     params: ->(context) { context }
```

---

### if

Conditional execution - step runs only if condition is true.

```ruby
step :step_name,
     with: ServiceClass,
     if: ->(context) { condition }
```

**Examples:**

```ruby
# Execute if value present
step :apply_discount,
     with: Order::ApplyDiscountService,
     if: ->(context) { context[:coupon_code].present? }

# Execute based on user role
step :notify_admin,
     with: Email::AdminNotificationService,
     if: ->(context) { context[:order].total > 1000 }

# Execute based on feature flag
step :track_analytics,
     with: Analytics::TrackService,
     if: ->(context) { FeatureFlag.enabled?(:analytics) }

# Multiple conditions
step :send_vip_email,
     with: Email::VipService,
     if: ->(context) {
       context[:user].vip? && context[:order].total > 500
     }

# Execute based on object state
step :charge_shipping,
     with: Order::ChargeShippingService,
     if: ->(context) { !context[:order].free_shipping? }
```

---

### unless

Inverse conditional - step runs only if condition is false.

```ruby
step :step_name,
     with: ServiceClass,
     unless: ->(context) { condition }
```

**Examples:**

```ruby
# Skip if free
step :charge_payment,
     with: Payment::ChargeService,
     unless: ->(context) { context[:order].free? }

# Skip if already completed
step :process_order,
     with: Order::ProcessService,
     unless: ->(context) { context[:order].processed? }

# Skip for admins
step :validate_permissions,
     with: PermissionService,
     unless: ->(context) { context[:user].admin? }
```

**Note:** Cannot use both `if` and `unless` on the same step.

---

### on_error

Custom error handling callback.

```ruby
step :step_name,
     with: ServiceClass,
     on_error: ->(context, error) {
       # Custom error handling
     }
```

**Examples:**

```ruby
# Log errors
step :charge_payment,
     with: Payment::ChargeService,
     on_error: ->(context, error) {
       PaymentLogger.log_failure(
         order: context[:order],
         error: error.message,
         user: context[:user]
       )
     }

# Send notifications
step :send_email,
     with: Email::ConfirmationService,
     on_error: ->(context, error) {
       ErrorNotifier.notify_admin(
         workflow: 'Order::Checkout',
         step: :send_email,
         error: error
       )
     }

# Update metrics
step :process_payment,
     with: Payment::ProcessService,
     on_error: ->(context, error) {
       Metrics.increment('payment.failures')
     }

# Store error in context
step :external_api_call,
     with: ExternalApiService,
     on_error: ->(context, error) {
       context[:api_error] = error.message
     }
```

**Important:** The error is still raised after the callback executes. `on_error` is for logging/tracking, not error suppression.

---

## Step Execution Order

Steps execute in the order they are defined:

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  step :first, with: FirstService      # 1. Executes first
  step :second, with: SecondService    # 2. Then this
  step :third, with: ThirdService      # 3. Then this
  step :fourth, with: FourthService    # 4. Finally this
end
```

### Execution Flow

```ruby
context = { initial: 'params' }

# Step 1
result = FirstService.new(user, params: context).call
context.merge!(result)  # Add result to context

# Step 2
result = SecondService.new(user, params: context).call
context.merge!(result)  # Add result to context

# Step 3
result = ThirdService.new(user, params: context).call
context.merge!(result)  # Add result to context

# Return final context
context
```

---

## Parameter Mapping Patterns

### Pattern 1: Direct Mapping

```ruby
step :create_order,
     with: Order::CreateService,
     params: ->(context) {
       {
         cart_id: context[:cart_id],
         user_id: context[:user_id]
       }
     }
```

### Pattern 2: Extracting from Objects

```ruby
step :charge_payment,
     with: Payment::ChargeService,
     params: ->(context) {
       order = context[:order]
       {
         order_id: order.id,
         amount: order.total,
         currency: order.currency,
         description: "Order ##{order.number}"
       }
     }
```

### Pattern 3: Transforming Data

```ruby
step :send_notification,
     with: Email::NotificationService,
     params: ->(context) {
       {
         to: context[:user].email,
         subject: "Order ##{context[:order].id} Confirmed",
         template: 'order_confirmation',
         data: {
           order_number: context[:order].number,
           total: format_currency(context[:order].total),
           items: context[:order].items.map(&:name)
         }
       }
     }
```

### Pattern 4: Merging Multiple Sources

```ruby
step :process_order,
     with: Order::ProcessService,
     params: ->(context) {
       base_params = {
         order_id: context[:order].id,
         user_id: context[:user].id
       }

       payment_params = if context[:payment]
         { payment_id: context[:payment].id }
       else
         {}
       end

       base_params.merge(payment_params)
     }
```

### Pattern 5: Using Defaults

```ruby
step :configure_settings,
     with: Settings::ConfigureService,
     params: ->(context) {
       {
         user_id: context[:user].id,
         locale: context[:locale] || 'en',
         timezone: context[:timezone] || 'UTC',
         currency: context[:currency] || 'USD'
       }
     }
```

---

## Conditional Step Patterns

### Pattern 1: Feature Flags

```ruby
step :track_analytics,
     with: Analytics::TrackService,
     if: ->(context) { FeatureFlag.enabled?(:analytics) }

step :use_new_algorithm,
     with: NewAlgorithmService,
     if: ->(context) { FeatureFlag.enabled?(:new_algorithm, user: context[:user]) }
```

### Pattern 2: User Roles

```ruby
step :apply_employee_discount,
     with: Order::EmployeeDiscountService,
     if: ->(context) { context[:user].employee? }

step :skip_payment,
     with: Order::SkipPaymentService,
     if: ->(context) { context[:user].admin? && context[:test_mode] }
```

### Pattern 3: Business Rules

```ruby
step :calculate_premium_shipping,
     with: Shipping::PremiumService,
     if: ->(context) { context[:order].total > 100 }

step :send_vip_notification,
     with: Email::VipService,
     if: ->(context) {
       context[:user].vip? && context[:order].total > 500
     }
```

### Pattern 4: Data Availability

```ruby
step :apply_coupon,
     with: Order::ApplyCouponService,
     if: ->(context) { context[:coupon_code].present? }

step :add_gift_message,
     with: Order::AddGiftMessageService,
     if: ->(context) { context[:gift_message].present? }

step :process_referral,
     with: User::ProcessReferralService,
     if: ->(context) { context[:referral_code].present? }
```

### Pattern 5: State Checks

```ruby
step :restock_items,
     with: Inventory::RestockService,
     if: ->(context) { context[:order].cancelled? }

step :send_reminder,
     with: Email::ReminderService,
     unless: ->(context) { context[:order].completed? }
```

---

## Advanced Step Configurations

### Combining Options

```ruby
step :apply_vip_discount,
     with: Order::VipDiscountService,
     if: ->(context) { context[:user].vip? },
     params: ->(context) {
       {
         order_id: context[:order].id,
         discount_rate: context[:user].vip_discount_rate
       }
     },
     on_error: ->(context, error) {
       logger.warn "VIP discount failed: #{error.message}"
     }
```

### Multiple Conditional Steps

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  # Base flow
  step :create_order, with: Order::CreateService

  # Optional steps based on conditions
  step :apply_coupon,
       with: Order::ApplyCouponService,
       if: ->(context) { context[:coupon_code].present? }

  step :apply_employee_discount,
       with: Order::EmployeeDiscountService,
       if: ->(context) { context[:user].employee? }

  step :apply_vip_discount,
       with: Order::VipDiscountService,
       if: ->(context) { context[:user].vip? }

  # Continue with required steps
  step :charge_payment, with: Payment::ChargeService
end
```

### Complex Parameter Logic

```ruby
step :process_payment,
     with: Payment::ProcessService,
     params: ->(context) {
       # Build complex parameters
       params = {
         order_id: context[:order].id,
         amount: context[:order].total
       }

       # Add payment method details
       case context[:payment_method]
       when 'credit_card'
         params[:card_token] = context[:card_token]
         params[:save_card] = context[:save_card]
       when 'paypal'
         params[:paypal_email] = context[:paypal_email]
       when 'stripe'
         params[:stripe_token] = context[:stripe_token]
       end

       # Add metadata
       params[:metadata] = {
         user_id: context[:user].id,
         ip_address: context[:ip_address],
         user_agent: context[:user_agent]
       }

       params
     }
```

---

## Error Handling Patterns

### Pattern 1: Logging

```ruby
step :critical_step,
     with: CriticalService,
     on_error: ->(context, error) {
       logger.error "Critical step failed", {
         workflow: self.class.name,
         user_id: context[:user]&.id,
         error: error.message,
         backtrace: error.backtrace.first(5)
       }
     }
```

### Pattern 2: External Notifications

```ruby
step :payment_processing,
     with: Payment::ProcessService,
     on_error: ->(context, error) {
       Sentry.capture_exception(error, extra: {
         order_id: context[:order]&.id,
         user_id: context[:user]&.id
       })

       SlackNotifier.notify_channel(
         channel: '#payments',
         message: "Payment failed for order #{context[:order]&.id}: #{error.message}"
       )
     }
```

### Pattern 3: Metrics Tracking

```ruby
step :external_api,
     with: ExternalApiService,
     on_error: ->(context, error) {
       Metrics.increment('external_api.errors', tags: {
         service: 'ExternalApiService',
         error_type: error.class.name
       })

       Metrics.timing('external_api.failure_time', context[:start_time])
     }
```

### Pattern 4: Cleanup Actions

```ruby
step :create_temp_file,
     with: FileProcessingService,
     on_error: ->(context, error) {
       # Clean up temporary file if it was created
       if context[:temp_file_path]
         File.delete(context[:temp_file_path]) rescue nil
       end
     }
```

---

## Step Naming Best Practices

### Use Descriptive Names

```ruby
# ✅ Good: Clear what the step does
step :create_order
step :charge_payment
step :send_confirmation_email

# ❌ Bad: Unclear names
step :step1
step :process
step :do_stuff
```

### Use Verb Phrases

```ruby
# ✅ Good: Action-oriented
step :validate_inventory
step :apply_discount
step :notify_customer

# ❌ Bad: Noun-based
step :validation
step :discount
step :notification
```

### Be Specific

```ruby
# ✅ Good: Specific about what's sent
step :send_order_confirmation_email
step :send_shipping_notification
step :send_payment_receipt

# ❌ Bad: Too generic
step :send_email
step :notify
step :process
```

---

## Testing Steps

### Testing Individual Steps

```ruby
# spec/workflows/order/checkout_workflow_spec.rb
RSpec.describe Order::CheckoutWorkflow do
  describe 'step :create_order' do
    it 'calls Order::CreateService with correct params' do
      expect(Order::CreateService).to receive(:new).with(
        user,
        params: hash_including(cart_id: cart.id)
      ).and_call_original

      described_class.new(user, params: { cart_id: cart.id }).call
    end
  end

  describe 'step :apply_coupon' do
    context 'when coupon code is present' do
      it 'applies the coupon' do
        expect {
          described_class.new(user, params: {
            cart_id: cart.id,
            coupon_code: 'SAVE20'
          }).call
        }.to change { Order.last&.discount }.from(0)
      end
    end

    context 'when coupon code is absent' do
      it 'skips the step' do
        expect(Order::ApplyCouponService).not_to receive(:new)

        described_class.new(user, params: { cart_id: cart.id }).call
      end
    end
  end
end
```

### Testing Step Conditions

```ruby
RSpec.describe Order::CheckoutWorkflow do
  describe 'conditional steps' do
    it 'applies employee discount for employees' do
      employee = create(:user, :employee)

      expect(Order::EmployeeDiscountService).to receive(:new).and_call_original

      described_class.new(employee, params: { cart_id: cart.id }).call
    end

    it 'skips employee discount for regular users' do
      regular_user = create(:user)

      expect(Order::EmployeeDiscountService).not_to receive(:new)

      described_class.new(regular_user, params: { cart_id: cart.id }).call
    end
  end
end
```

### Testing Error Handling

```ruby
RSpec.describe Order::CheckoutWorkflow do
  describe 'error handling' do
    it 'logs payment errors' do
      allow(Payment::ChargeService).to receive(:new).and_raise(
        BetterService::Errors::Runtime::ExecutionError.new("Card declined")
      )

      expect(PaymentLogger).to receive(:log_failure)

      expect {
        described_class.new(user, params: { cart_id: cart.id }).call
      }.to raise_error(BetterService::Errors::Runtime::ExecutionError)
    end
  end
end
```

---

## Common Pitfalls

### Pitfall 1: Forgetting Parameter Mapping

```ruby
# ❌ Bad: Service expects different params than workflow provides
step :charge_payment, with: Payment::ChargeService
# ChargeService expects { order_id, amount }
# But context has { order: <object> }

# ✅ Good: Map parameters explicitly
step :charge_payment,
     with: Payment::ChargeService,
     params: ->(context) {
       {
         order_id: context[:order].id,
         amount: context[:order].total
       }
     }
```

### Pitfall 2: Complex Conditions in if/unless

```ruby
# ❌ Bad: Hard to read and test
step :do_something,
     if: ->(ctx) {
       ctx[:a] && !ctx[:b] || (ctx[:c] && ctx[:d].present?) && !ctx[:e]
     }

# ✅ Good: Extract to method
step :do_something, if: :should_do_something?

def should_do_something?(context)
  has_condition_a = context[:a] && !context[:b]
  has_condition_b = context[:c] && context[:d].present?

  (has_condition_a || has_condition_b) && !context[:e]
end
```

### Pitfall 3: Side Effects in on_error

```ruby
# ❌ Bad: Swallowing errors
step :important_step,
     with: ImportantService,
     on_error: ->(context, error) {
       # Don't try to suppress errors here
       # The error will still be raised
     }

# ✅ Good: Just log/track
step :important_step,
     with: ImportantService,
     on_error: ->(context, error) {
       ErrorLogger.log(error)
       Metrics.increment('important_step.failures')
       # Error still bubbles up - this is expected
     }
```

---

**See also:**
- [Workflows Introduction](01_workflows_introduction.md)
- [Workflow Context](03_workflow_context.md)
- [Workflow Lifecycle](04_workflow_lifecycle.md)
- [Workflow Examples](05_workflow_examples.md)
