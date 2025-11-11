# Best Practices Examples

## Always Use DSL Methods
Use process_with, search_with, respond_with blocks.

```ruby
class Product::CreateService < BetterService::CreateService
  model_class Product

  schema do
    required(:name).filled(:string)
  end

  # ✅ Use DSL methods
  search_with do
    { category: Category.find(params[:category_id]) }
  end

  process_with do |data|
    resource = model_class.create!(params)
    { resource: resource }
  end

  respond_with do |data|
    { resource: ProductPresenter.present(data[:resource]) }
  end
end
```

## Use Workflows for Multi-Step Operations
Never call services from services.

```ruby
# ✅ CORRECT: Use workflow
class Order::CheckoutWorkflow < BetterService::Workflow
  schema do
    required(:cart_id).filled(:integer)
    required(:payment_method).filled(:string)
  end

  step :create_order, with: Order::CreateService
  step :charge_payment, with: Payment::ChargeService
  step :clear_cart, with: Cart::ClearService
  step :send_confirmation, with: Email::ConfirmationService
end

# Usage
result = Order::CheckoutWorkflow.new(current_user, params: checkout_params).call
order = result[:order]
```

## Always Validate Parameters
Use Dry::Schema for comprehensive validation.

```ruby
class User::CreateService < BetterService::CreateService
  model_class User

  schema do
    required(:email).filled(:string, format?: /@/)
    required(:password).filled(:string, min_size?: 8)
    required(:first_name).filled(:string)
    required(:last_name).filled(:string)
    optional(:phone).maybe(:string, format?: /\A\+?[\d\s\-\(\)]+\z/)
    optional(:age).maybe(:integer, gteq?: 18, lteq?: 120)
  end

  process_with do |data|
    resource = model_class.create!(params)
    { resource: resource }
  end
end
```

## Use Authorization for Sensitive Operations
Protect operations with proper authorization.

```ruby
class Document::DestroyService < BetterService::DestroyService
  model_class Document

  schema do
    required(:id).filled(:integer)
  end

  # ✅ Always authorize sensitive operations
  authorize_with do
    resource = model_class.find(params[:id])
    user.admin? || resource.user_id == user.id
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    data[:resource].destroy!
    { resource: data[:resource] }
  end
end
```

## Use Presenters for Consistent Output
Format data with dedicated presenters.

```ruby
class Product::ShowService < BetterService::ShowService
  model_class Product
  presenter ProductPresenter

  search_with do
    { resource: model_class.find(params[:id]) }
  end
end

class ProductPresenter
  def self.present(product)
    {
      id: product.id,
      name: product.name,
      price: product.price.to_f,
      category: product.category.name,
      created_at: product.created_at.iso8601
    }
  end
end
```

## Enable Caching for Read Operations
Use cache contexts for better performance.

```ruby
class Product::IndexService < BetterService::IndexService
  model_class Product
  cache_contexts :products

  schema do
    optional(:category_id).maybe(:integer)
  end

  search_with do
    scope = model_class.all
    scope = scope.where(category_id: params[:category_id]) if params[:category_id]
    { items: scope }
  end
end

# Invalidate cache after modifications
class Product::CreateService < BetterService::CreateService
  model_class Product
  invalidate_cache_contexts :products

  process_with do |data|
    resource = model_class.create!(params)
    { resource: resource }
  end
end
```

## Use Conditional Steps in Workflows
Execute steps only when needed.

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  schema do
    required(:cart_id).filled(:integer)
    optional(:coupon_code).maybe(:string)
    optional(:gift_wrap).maybe(:bool)
  end

  step :create_order, with: Order::CreateService

  # ✅ Conditional steps
  step :apply_coupon,
       with: Order::ApplyCouponService,
       if: ->(context) { context[:coupon_code].present? }

  step :add_gift_wrap,
       with: Order::GiftWrapService,
       if: ->(context) { context[:gift_wrap] }

  step :charge_payment, with: Payment::ChargeService
end
```

## Handle Errors Gracefully
Log errors and provide context.

```ruby
class Payment::ChargeService < BetterService::ActionService
  model_class Order
  action_name :charge

  schema do
    required(:order_id).filled(:integer)
    required(:amount).filled(:float)
  end

  search_with do
    { order: model_class.find(params[:order_id]) }
  end

  process_with do |data|
    begin
      charge = Stripe::Charge.create(
        amount: (params[:amount] * 100).to_i,
        currency: 'usd'
      )

      data[:order].update!(
        payment_status: 'paid',
        charge_id: charge.id
      )

      { order: data[:order], charge: charge }
    rescue Stripe::CardError => e
      # Log error with context
      Rails.logger.error("Payment failed: #{e.message}")
      Sentry.capture_exception(e, extra: {
        order_id: data[:order].id,
        amount: params[:amount]
      })

      raise BetterService::Errors::Runtime::ExecutionError.new(
        "Payment failed: #{e.message}"
      )
    end
  end
end
```

## Keep Services Focused
One service, one responsibility.

```ruby
# ✅ Good: Focused services
class User::CreateService < BetterService::CreateService
  # Only creates user
  model_class User

  process_with do |data|
    resource = model_class.create!(params)
    { resource: resource }
  end
end

class Profile::CreateService < BetterService::CreateService
  # Only creates profile
  model_class Profile

  process_with do |data|
    resource = model_class.create!(params)
    { resource: resource }
  end
end

# Compose them in workflow
class User::RegistrationWorkflow < BetterService::Workflow
  step :create_user, with: User::CreateService
  step :create_profile, with: Profile::CreateService
end
```

## Use Error Handlers in Workflows
Track failures without stopping rollback.

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  schema do
    required(:cart_id).filled(:integer)
  end

  step :create_order, with: Order::CreateService

  step :charge_payment,
       with: Payment::ChargeService,
       on_error: ->(context, error) {
         # ✅ Log error for monitoring
         PaymentLogger.log_failure(
           order: context[:order],
           error: error.message,
           user: context[:user]
         )

         Metrics.increment('checkout.payment_failures')

         # Error still bubbles up and triggers rollback
       }

  step :send_confirmation, with: Email::ConfirmationService
end
```

## Test Services Thoroughly
Write comprehensive tests for services.

```ruby
# ✅ Example RSpec test
RSpec.describe Product::CreateService do
  let(:user) { create(:user, :admin) }

  describe '#call' do
    context 'with valid parameters' do
      let(:params) do
        {
          name: 'Test Product',
          price: 99.99,
          category_id: create(:category).id
        }
      end

      it 'creates a product' do
        expect {
          described_class.new(user, params: params).call
        }.to change(Product, :count).by(1)
      end

      it 'returns the product' do
        result = described_class.new(user, params: params).call
        expect(result[:resource]).to be_a(Product)
        expect(result[:resource].name).to eq('Test Product')
      end
    end

    context 'with invalid parameters' do
      it 'raises validation error' do
        expect {
          described_class.new(user, params: {}).call
        }.to raise_error(BetterService::Errors::Runtime::SchemaValidationError)
      end
    end

    context 'without authorization' do
      let(:regular_user) { create(:user) }

      it 'raises authorization error' do
        expect {
          described_class.new(regular_user, params: params).call
        }.to raise_error(BetterService::Errors::Runtime::AuthorizationError)
      end
    end
  end
end
```

## Monitor Services with Instrumentation

Always enable instrumentation for production monitoring and observability.

### Enable Built-in Subscribers

```ruby
# config/initializers/better_service.rb
BetterService.configure do |config|
  # Enable instrumentation (default: true)
  config.instrumentation_enabled = true

  # Enable metrics collection (default: true)
  config.stats_subscriber_enabled = true

  # Enable automatic logging (default: true)
  config.log_subscriber_enabled = true
end
```

### Track Performance with StatsSubscriber

```ruby
# Access service statistics
stats = BetterService::Subscribers::StatsSubscriber.stats
# => {
#   "Product::CreateService" => {
#     executions: 150,
#     successes: 148,
#     failures: 2,
#     avg_duration: 30.0,
#     cache_hit_rate: 75.0
#   }
# }

# Get aggregate summary
summary = BetterService::Subscribers::StatsSubscriber.summary
# => {
#   total_services: 5,
#   total_executions: 1250,
#   success_rate: 98.8,
#   avg_duration: 28.5
# }
```

### Exclude Sensitive Services

```ruby
# config/initializers/better_service.rb
BetterService.configure do |config|
  # Exclude sensitive services from instrumentation
  config.instrumentation_excluded_services = [
    "Authentication::LoginService",
    "User::ChangePasswordService",
    "Payment::ProcessCreditCardService"
  ]

  # Disable params in production for privacy
  config.instrumentation_include_args = !Rails.env.production?
end
```

### Create Custom Subscribers

```ruby
# app/subscribers/alert_subscriber.rb
class AlertSubscriber
  def self.attach
    ActiveSupport::Notifications.subscribe("service.failed") do |name, start, finish, id, payload|
      if payload[:service_name].match?(/^Payment::/)
        SlackNotifier.alert(
          "Critical payment service failed: #{payload[:error_message]}"
        )
      end
    end
  end
end

# In initializer
AlertSubscriber.attach
```

### Best Practices for Instrumentation

✅ **DO:**
- Enable StatsSubscriber to track service health
- Exclude high-frequency, low-value services (health checks, session refresh)
- Sanitize sensitive params in custom subscribers
- Use background jobs for heavy processing in subscribers
- Monitor P95/P99 latency, not just averages

❌ **DON'T:**
- Include passwords, tokens, or credit cards in instrumentation
- Track every single service call (exclude noise)
- Make blocking API calls in subscribers
- Use high-cardinality tags (user IDs, session IDs)

**See also:**
- Advanced instrumentation examples: `/context7/advanced/`
- Full instrumentation documentation: `/docs/advanced/instrumentation.md`
