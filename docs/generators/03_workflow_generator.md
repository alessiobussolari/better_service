# Workflow Generator

## Overview

The workflow generator creates workflow files that orchestrate multiple services in sequence with rollback support.

## Command

```bash
rails g serviceable:workflow WorkflowName [options]
```

## Generated File

```ruby
# app/workflows/workflow_name_workflow.rb
class WorkflowNameWorkflow < BetterService::Workflow
  schema do
    # Define your workflow parameters
  end

  step :step_one, with: StepOneService
  step :step_two, with: StepTwoService
end
```

## Basic Usage

### Simple Workflow

```bash
$ rails g serviceable:workflow Order::Checkout

create  app/workflows/order/checkout_workflow.rb
```

```ruby
# app/workflows/order/checkout_workflow.rb
module Order
  class CheckoutWorkflow < BetterService::Workflow
    schema do
      required(:order_id).filled(:integer)
      required(:payment_method).filled(:string)
    end

    step :validate_order, with: Order::ValidateService
    step :charge_payment, with: Payment::ChargeService
    step :confirm_order, with: Order::ConfirmService
    step :send_confirmation, with: Email::ConfirmationService
  end
end
```

### Usage

```ruby
# Execute workflow
result = Order::CheckoutWorkflow.new(current_user, params: {
  order_id: 123,
  payment_method: 'credit_card'
}).call

if result[:success]
  order = result[:order]
  redirect_to order_path(order), notice: "Order placed successfully"
else
  # One of the steps failed - everything was rolled back
  redirect_to cart_path, alert: "Checkout failed"
end
```

## Workflow Structure

### Schema Definition

Define parameters for the entire workflow:

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  schema do
    required(:order_id).filled(:integer)
    required(:payment_method).filled(:string)
    required(:shipping_address).hash do
      required(:street).filled(:string)
      required(:city).filled(:string)
      required(:zip).filled(:string)
    end

    optional(:coupon_code).maybe(:string)
    optional(:save_payment_method).maybe(:bool)
  end

  # Steps...
end
```

### Step Definition

Define the sequence of services to execute:

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  # Basic step
  step :validate_order, with: Order::ValidateService

  # Step with parameter mapping
  step :charge_payment,
       with: Payment::ChargeService,
       params: ->(context) {
         {
           order_id: context[:order_id],
           amount: context[:order].total,
           payment_method: context[:payment_method]
         }
       }

  # Conditional step
  step :apply_discount,
       with: Order::ApplyDiscountService,
       if: ->(context) { context[:coupon_code].present? }

  # Final step
  step :send_confirmation,
       with: Email::ConfirmationService
end
```

## Step Options

### with (Required)

Specifies the service to execute:

```ruby
step :create_order, with: Order::CreateService
```

### params

Maps workflow context to service parameters:

```ruby
step :charge_payment,
     with: Payment::ChargeService,
     params: ->(context) {
       {
         order_id: context[:order]&.id,
         amount: context[:total],
         method: context[:payment_method]
       }
     }
```

### if

Conditional execution:

```ruby
step :apply_discount,
     with: Order::ApplyDiscountService,
     if: ->(context) { context[:coupon_code].present? }

step :notify_vip,
     with: Email::VipNotificationService,
     if: ->(context) { context[:order].user.vip? }
```

### unless

Inverse conditional:

```ruby
step :charge_full_price,
     with: Payment::ChargeService,
     unless: ->(context) { context[:free_order] }
```

### on_error

Custom error handling:

```ruby
step :charge_payment,
     with: Payment::ChargeService,
     on_error: ->(context, error) {
       PaymentLogger.log_failure(context[:order], error)
       # Error still bubbles up, but you've logged it
     }
```

## Complete Examples

### Example 1: Order Checkout

```bash
$ rails g serviceable:workflow Order::Checkout

create  app/workflows/order/checkout_workflow.rb
```

```ruby
# app/workflows/order/checkout_workflow.rb
module Order
  class CheckoutWorkflow < BetterService::Workflow
    schema do
      required(:cart_id).filled(:integer)
      required(:payment_method).filled(:string)
      required(:shipping_address).hash do
        required(:street).filled(:string)
        required(:city).filled(:string)
        required(:zip).filled(:string)
        required(:country).filled(:string)
      end

      optional(:coupon_code).maybe(:string)
      optional(:gift_message).maybe(:string)
    end

    # Step 1: Validate cart and create order
    step :create_order,
         with: Order::CreateFromCartService,
         params: ->(context) {
           {
             cart_id: context[:cart_id],
             shipping_address: context[:shipping_address],
             gift_message: context[:gift_message]
           }
         }

    # Step 2: Apply coupon if present
    step :apply_coupon,
         with: Order::ApplyCouponService,
         if: ->(context) { context[:coupon_code].present? },
         params: ->(context) {
           {
             order_id: context[:order].id,
             coupon_code: context[:coupon_code]
           }
         }

    # Step 3: Calculate shipping
    step :calculate_shipping,
         with: Order::CalculateShippingService,
         params: ->(context) {
           {
             order_id: context[:order].id,
             address: context[:shipping_address]
           }
         }

    # Step 4: Charge payment
    step :charge_payment,
         with: Payment::ChargeService,
         params: ->(context) {
           {
             order_id: context[:order].id,
             amount: context[:order].total,
             payment_method: context[:payment_method]
           }
         }

    # Step 5: Confirm order
    step :confirm_order,
         with: Order::ConfirmService,
         params: ->(context) {
           {
             order_id: context[:order].id,
             payment_id: context[:payment].id
           }
         }

    # Step 6: Reserve inventory
    step :reserve_inventory,
         with: Inventory::ReserveService,
         params: ->(context) {
           {
             order_id: context[:order].id
           }
         }

    # Step 7: Clear cart
    step :clear_cart,
         with: Cart::ClearService,
         params: ->(context) {
           {
             cart_id: context[:cart_id]
           }
         }

    # Step 8: Send confirmation email
    step :send_confirmation,
         with: Email::OrderConfirmationService,
         params: ->(context) {
           {
             order_id: context[:order].id
           }
         }
  end
end
```

### Example 2: User Registration

```bash
$ rails g serviceable:workflow User::Registration

create  app/workflows/user/registration_workflow.rb
```

```ruby
# app/workflows/user/registration_workflow.rb
module User
  class RegistrationWorkflow < BetterService::Workflow
    self._allow_nil_user = true  # No user yet!

    schema do
      required(:email).filled(:string, format?: /@/)
      required(:password).filled(:string, min_size?: 8)
      required(:password_confirmation).filled(:string)
      required(:first_name).filled(:string)
      required(:last_name).filled(:string)

      optional(:referral_code).maybe(:string)

      rule(:password, :password_confirmation) do
        if values[:password] != values[:password_confirmation]
          key(:password_confirmation).failure('must match password')
        end
      end
    end

    # Step 1: Validate email uniqueness
    step :validate_email,
         with: User::ValidateEmailService

    # Step 2: Process referral if present
    step :process_referral,
         with: User::ProcessReferralService,
         if: ->(context) { context[:referral_code].present? }

    # Step 3: Create user account
    step :create_user,
         with: User::CreateService

    # Step 4: Create default settings
    step :create_settings,
         with: User::CreateSettingsService,
         params: ->(context) {
           {
             user_id: context[:user].id
           }
         }

    # Step 5: Generate verification token
    step :generate_token,
         with: User::GenerateVerificationTokenService,
         params: ->(context) {
           {
             user_id: context[:user].id
           }
         }

    # Step 6: Send welcome email
    step :send_welcome,
         with: Email::WelcomeService,
         params: ->(context) {
           {
             user_id: context[:user].id
           }
         }

    # Step 7: Send verification email
    step :send_verification,
         with: Email::VerificationService,
         params: ->(context) {
           {
             user_id: context[:user].id,
             token: context[:verification_token]
           }
         }

    # Step 8: Track signup event
    step :track_signup,
         with: Analytics::TrackSignupService,
         params: ->(context) {
           {
             user_id: context[:user].id,
             referral_code: context[:referral_code]
           }
         }
  end
end
```

### Example 3: Article Publishing

```bash
$ rails g serviceable:workflow Article::Publishing

create  app/workflows/article/publishing_workflow.rb
```

```ruby
# app/workflows/article/publishing_workflow.rb
module Article
  class PublishingWorkflow < BetterService::Workflow
    schema do
      required(:article_id).filled(:integer)
      optional(:publish_at).maybe(:time)
      optional(:notify_subscribers).maybe(:bool)
      optional(:tweet).maybe(:bool)
    end

    # Step 1: Validate article
    step :validate_article,
         with: Article::ValidateService,
         params: ->(context) {
           {
             id: context[:article_id]
           }
         }

    # Step 2: Generate SEO metadata
    step :generate_seo,
         with: Article::GenerateSEOService,
         params: ->(context) {
           {
             article_id: context[:article].id
           }
         }

    # Step 3: Optimize images
    step :optimize_images,
         with: Article::OptimizeImagesService,
         params: ->(context) {
           {
             article_id: context[:article].id
           }
         }

    # Step 4: Publish article
    step :publish,
         with: Article::PublishService,
         params: ->(context) {
           {
             id: context[:article].id,
             publish_at: context[:publish_at]
           }
         }

    # Step 5: Update search index
    step :index_search,
         with: Article::IndexSearchService,
         params: ->(context) {
           {
             article_id: context[:article].id
           }
         }

    # Step 6: Notify subscribers (optional)
    step :notify_subscribers,
         with: Article::NotifySubscribersService,
         if: ->(context) { context[:notify_subscribers] != false },
         params: ->(context) {
           {
             article_id: context[:article].id
           }
         }

    # Step 7: Post to Twitter (optional)
    step :post_tweet,
         with: Article::TweetService,
         if: ->(context) { context[:tweet] == true },
         params: ->(context) {
           {
             article_id: context[:article].id
           }
         }
  end
end
```

## Workflow Context

The workflow context accumulates results from each step:

```ruby
# Initial context from params
context = {
  order_id: 123,
  payment_method: 'credit_card'
}

# After step :create_order
context = {
  order_id: 123,
  payment_method: 'credit_card',
  order: #<Order id: 123, ...>  # Added by CreateService
}

# After step :charge_payment
context = {
  order_id: 123,
  payment_method: 'credit_card',
  order: #<Order id: 123, ...>,
  payment: #<Payment id: 456, ...>  # Added by ChargeService
}

# And so on...
```

## Rollback Behavior

If any step fails, all previous steps are automatically rolled back:

```ruby
# In controller
begin
  result = Order::CheckoutWorkflow.new(current_user, params: checkout_params).call

  if result[:success]
    # All steps succeeded
    redirect_to order_path(result[:order])
  end
rescue BetterService::Errors::Runtime::ValidationError => e
  # Validation failed, nothing was committed
  flash[:error] = e.message
  redirect_to cart_path
rescue BetterService::Errors::Runtime::ExecutionError => e
  # A step failed (e.g., payment declined)
  # Everything was rolled back
  flash[:error] = "Checkout failed: #{e.message}"
  redirect_to cart_path
end
```

## Best Practices

### 1. Keep Steps Small and Focused

```ruby
# ✅ Good: Each step does one thing
step :create_order, with: Order::CreateService
step :charge_payment, with: Payment::ChargeService
step :send_confirmation, with: Email::ConfirmationService

# ❌ Bad: One giant step
step :do_everything, with: Order::DoEverythingService
```

### 2. Use Descriptive Step Names

```ruby
# ✅ Good: Clear what happens
step :validate_inventory
step :charge_payment
step :send_confirmation

# ❌ Bad: Unclear names
step :step1
step :process
step :finish
```

### 3. Handle Errors Appropriately

```ruby
# ✅ Good: Log errors for important steps
step :charge_payment,
     with: Payment::ChargeService,
     on_error: ->(context, error) {
       PaymentLogger.log_failure(context[:order], error)
       ErrorNotifier.notify_admin(error)
     }
```

### 4. Use Conditional Steps Wisely

```ruby
# ✅ Good: Clear conditions
step :apply_discount,
     if: ->(context) { context[:coupon_code].present? }

step :charge_payment,
     unless: ->(context) { context[:order].free? }

# ❌ Bad: Complex conditions
step :maybe_do_something,
     if: ->(context) {
       context[:a] && !context[:b] || (context[:c] && context[:d].present?)
     }
```

### 5. Map Parameters Explicitly

```ruby
# ✅ Good: Clear parameter mapping
step :charge_payment,
     with: Payment::ChargeService,
     params: ->(context) {
       {
         order_id: context[:order].id,
         amount: context[:order].total,
         method: context[:payment_method]
       }
     }

# ❌ Bad: Implicit parameters (might not work)
step :charge_payment, with: Payment::ChargeService
```

## Testing Workflows

### RSpec

```ruby
# spec/workflows/order/checkout_workflow_spec.rb
require 'rails_helper'

RSpec.describe Order::CheckoutWorkflow do
  let(:user) { create(:user) }
  let(:cart) { create(:cart, :with_items, user: user) }

  let(:valid_params) do
    {
      cart_id: cart.id,
      payment_method: 'credit_card',
      shipping_address: {
        street: '123 Main St',
        city: 'New York',
        zip: '10001',
        country: 'USA'
      }
    }
  end

  describe '#call' do
    it 'successfully completes checkout' do
      result = described_class.new(user, params: valid_params).call

      expect(result[:success]).to be true
      expect(result[:order]).to be_a(Order)
      expect(result[:order].status).to eq('confirmed')
      expect(result[:payment]).to be_a(Payment)
    end

    it 'creates order from cart' do
      expect {
        described_class.new(user, params: valid_params).call
      }.to change(Order, :count).by(1)
    end

    it 'charges payment' do
      expect {
        described_class.new(user, params: valid_params).call
      }.to change(Payment, :count).by(1)
    end

    it 'clears cart after success' do
      described_class.new(user, params: valid_params).call

      expect(cart.reload.items).to be_empty
    end

    context 'when payment fails' do
      before do
        allow(Payment::ChargeService).to receive(:new).and_raise(
          BetterService::Errors::Runtime::ExecutionError.new("Card declined")
        )
      end

      it 'rolls back order creation' do
        expect {
          described_class.new(user, params: valid_params).call rescue nil
        }.not_to change(Order, :count)
      end

      it 'does not clear cart' do
        described_class.new(user, params: valid_params).call rescue nil

        expect(cart.reload.items).not_to be_empty
      end
    end

    context 'with coupon code' do
      let(:coupon) { create(:coupon, code: 'SAVE20') }

      it 'applies discount' do
        result = described_class.new(user, params: valid_params.merge(
          coupon_code: 'SAVE20'
        )).call

        expect(result[:order].discount).to be > 0
      end
    end
  end
end
```

## Generator Options

### --namespace

Generate in a namespace:

```bash
rails g serviceable:workflow Admin::Product::Approval
```

Creates: `app/workflows/admin/product/approval_workflow.rb`

### --skip / --force

```bash
# Skip if exists
rails g serviceable:workflow Order::Checkout --skip

# Overwrite if exists
rails g serviceable:workflow Order::Checkout --force
```

## File Structure

```
app/
└── workflows/
    ├── order/
    │   ├── checkout_workflow.rb
    │   └── refund_workflow.rb
    ├── user/
    │   └── registration_workflow.rb
    └── article/
        └── publishing_workflow.rb
```

---

**See also:**
- [Generators Overview](01_generators_overview.md)
- [Service Generators](02_service_generators.md)
- [Workflows Introduction](../workflows/01_workflows_introduction.md)
- [Workflow Examples](../workflows/05_workflow_examples.md)
