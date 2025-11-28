# Error Handling Examples

## Controller Error Handling

### Basic Rescue Pattern

```ruby
class ProductsController < ApplicationController
  def create
    result = Products::CreateService.new(current_user, params: product_params).call
    @product = result[:resource]
    redirect_to @product, notice: result[:message]
  rescue BetterService::Errors::Runtime::ValidationError => e
    @errors = e.context[:validation_errors]
    render :new, status: :unprocessable_entity
  rescue BetterService::Errors::Runtime::AuthorizationError => e
    redirect_to root_path, alert: "You are not authorized to create products"
  rescue BetterService::Errors::Runtime::DatabaseError => e
    Rails.logger.error("Database error: #{e.to_h}")
    @errors = { base: ["Could not save product"] }
    render :new, status: :internal_server_error
  end
end
```

### Global Error Handler

```ruby
class ApplicationController < ActionController::Base
  rescue_from BetterService::BetterServiceError, with: :handle_service_error

  private

  def handle_service_error(error)
    log_error(error)

    case error.code
    when :validation_failed
      respond_with_validation_errors(error)
    when :unauthorized
      respond_with_unauthorized(error)
    when :resource_not_found
      respond_with_not_found(error)
    when :database_error, :transaction_error
      respond_with_server_error(error)
    else
      respond_with_server_error(error)
    end
  end

  def respond_with_validation_errors(error)
    respond_to do |format|
      format.html do
        flash.now[:alert] = "Please fix the errors below"
        render action_for_error, status: :unprocessable_entity
      end
      format.json do
        render json: {
          error: "Validation failed",
          errors: error.context[:validation_errors]
        }, status: :unprocessable_entity
      end
    end
  end

  def respond_with_unauthorized(error)
    respond_to do |format|
      format.html { redirect_to root_path, alert: "Not authorized" }
      format.json { render json: { error: "Unauthorized" }, status: :forbidden }
    end
  end

  def respond_with_not_found(error)
    respond_to do |format|
      format.html { render "errors/not_found", status: :not_found }
      format.json { render json: { error: "Not found" }, status: :not_found }
    end
  end

  def respond_with_server_error(error)
    respond_to do |format|
      format.html { render "errors/internal_error", status: :internal_server_error }
      format.json { render json: { error: "Internal error" }, status: :internal_server_error }
    end
  end

  def log_error(error)
    Rails.logger.error({
      error_class: error.class.name,
      code: error.code,
      message: error.message,
      context: error.context,
      user_id: current_user&.id,
      request_path: request.path
    }.to_json)
  end
end
```

## API Error Handling

### JSON API Controller

```ruby
class Api::V1::ProductsController < Api::V1::BaseController
  def create
    result = Products::CreateService.new(current_user, params: product_params).call

    render json: {
      data: ProductSerializer.new(result[:resource]),
      meta: result[:metadata]
    }, status: :created
  end

  def update
    result = Products::UpdateService.new(current_user, params: update_params).call

    render json: {
      data: ProductSerializer.new(result[:resource]),
      meta: result[:metadata]
    }
  end

  def destroy
    Products::DestroyService.new(current_user, params: { id: params[:id] }).call

    head :no_content
  end
end

class Api::V1::BaseController < ActionController::API
  rescue_from BetterService::Errors::Runtime::ValidationError do |error|
    render json: {
      error: {
        code: error.code,
        message: "Validation failed",
        details: error.context[:validation_errors]
      }
    }, status: :unprocessable_entity
  end

  rescue_from BetterService::Errors::Runtime::AuthorizationError do |error|
    render json: {
      error: {
        code: error.code,
        message: "Forbidden"
      }
    }, status: :forbidden
  end

  rescue_from BetterService::Errors::Runtime::ResourceNotFoundError do |error|
    render json: {
      error: {
        code: error.code,
        message: "Resource not found",
        resource: error.context[:model_class],
        id: error.context[:id]
      }
    }, status: :not_found
  end

  rescue_from BetterService::BetterServiceError do |error|
    Rails.logger.error(error.to_h)

    render json: {
      error: {
        code: error.code,
        message: "Internal server error"
      }
    }, status: :internal_server_error
  end
end
```

## Accessing Validation Errors

### In Controller

```ruby
def create
  result = Products::CreateService.new(current_user, params: product_params).call
  redirect_to result[:resource]
rescue BetterService::Errors::Runtime::ValidationError => e
  # Access specific field errors
  @name_errors = e.context[:validation_errors][:name]
  @price_errors = e.context[:validation_errors][:price]

  # Or all errors
  @all_errors = e.context[:validation_errors]

  # Format for form
  @product = Product.new(product_params)
  e.context[:validation_errors].each do |field, messages|
    messages.each { |msg| @product.errors.add(field, msg) }
  end

  render :new
end
```

### In View

```erb
<% if @product.errors.any? %>
  <div class="alert alert-danger">
    <h4><%= pluralize(@product.errors.count, "error") %> prevented saving:</h4>
    <ul>
      <% @product.errors.full_messages.each do |message| %>
        <li><%= message %></li>
      <% end %>
    </ul>
  </div>
<% end %>
```

## Logging Errors

### Structured Logging

```ruby
rescue BetterService::BetterServiceError => e
  # Log full error hash
  Rails.logger.error({
    event: "service_error",
    error: e.to_h,
    request_id: request.request_id,
    user_id: current_user&.id
  }.to_json)
end
```

### Error Tracking Integration

```ruby
# With Sentry
rescue BetterService::BetterServiceError => e
  Sentry.capture_exception(e, extra: {
    code: e.code,
    context: e.context,
    service: e.context[:service]
  })
  raise
end

# With Honeybadger
rescue BetterService::BetterServiceError => e
  Honeybadger.notify(e, context: {
    code: e.code,
    service_context: e.context
  })
  raise
end
```

## Testing Error Handling

### Testing Validation Errors

```ruby
class Products::CreateServiceTest < ActiveSupport::TestCase
  test "raises ValidationError for missing name" do
    error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
      Products::CreateService.new(users(:admin), params: { price: 10.00 })
    end

    assert_equal :validation_failed, error.code
    assert error.context[:validation_errors].key?(:name)
    assert_includes error.context[:validation_errors][:name], "is missing"
  end

  test "raises ValidationError for invalid price" do
    error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
      Products::CreateService.new(users(:admin), params: { name: "Widget", price: -10 })
    end

    assert_equal :validation_failed, error.code
    assert error.context[:validation_errors].key?(:price)
  end
end
```

### Testing Authorization Errors

```ruby
class Products::UpdateServiceTest < ActiveSupport::TestCase
  test "raises AuthorizationError for non-owner" do
    product = products(:other_user_product)
    user = users(:regular_user)

    service = Products::UpdateService.new(user, params: { id: product.id, name: "New Name" })

    error = assert_raises(BetterService::Errors::Runtime::AuthorizationError) do
      service.call
    end

    assert_equal :unauthorized, error.code
    assert_equal user.id, error.context[:user_id]
  end
end
```

### Testing Resource Not Found

```ruby
class Products::ShowServiceTest < ActiveSupport::TestCase
  test "raises ResourceNotFoundError for non-existent product" do
    error = assert_raises(BetterService::Errors::Runtime::ResourceNotFoundError) do
      Products::ShowService.new(users(:admin), params: { id: 999999 }).call
    end

    assert_equal :resource_not_found, error.code
    assert_equal 999999, error.context[:id]
    assert_equal "Product", error.context[:model_class]
  end
end
```

### Testing Database Errors

```ruby
class Products::CreateServiceTest < ActiveSupport::TestCase
  test "raises DatabaseError on unique constraint violation" do
    existing = products(:existing_product)

    error = assert_raises(BetterService::Errors::Runtime::DatabaseError) do
      Products::CreateService.new(
        users(:admin),
        params: { name: "New", sku: existing.sku }  # Duplicate SKU
      ).call
    end

    assert_equal :database_error, error.code
    assert_kind_of ActiveRecord::RecordInvalid, error.original_error
  end
end
```

### Testing Workflow Errors

```ruby
class Order::CheckoutWorkflowTest < ActiveSupport::TestCase
  test "raises StepExecutionError when payment fails" do
    # Setup failing payment
    Payment::ChargeService.any_instance.stubs(:call).raises(
      BetterService::Errors::Runtime::ExecutionError.new("Payment declined")
    )

    error = assert_raises(BetterService::Errors::Workflowable::Runtime::StepExecutionError) do
      Order::CheckoutWorkflow.new(users(:admin), params: { cart_id: 1 }).call
    end

    assert_equal :step_failed, error.code
    assert_equal :charge_payment, error.context[:step]
  end

  test "raises RollbackError when rollback fails" do
    # Complex test for rollback failure scenario
  end
end
```

## Custom Error Wrapping

### Wrapping External Service Errors

```ruby
class Payment::ChargeService < BetterService::Services::ActionService
  process_with do |data|
    begin
      charge = Stripe::Charge.create(
        amount: data[:amount],
        currency: 'usd',
        source: params[:token]
      )
      { resource: charge }
    rescue Stripe::CardError => e
      raise BetterService::Errors::Runtime::ExecutionError.new(
        "Payment failed: #{e.message}",
        code: :payment_failed,
        original_error: e,
        context: {
          service: self.class.name,
          stripe_code: e.code
        }
      )
    rescue Stripe::APIError => e
      raise BetterService::Errors::Runtime::ExecutionError.new(
        "Payment service unavailable",
        code: :payment_service_error,
        original_error: e,
        context: { service: self.class.name }
      )
    end
  end
end
```

### Custom Error Class

```ruby
module BetterService
  module Errors
    module Runtime
      class PaymentError < RuntimeError
        def initialize(message, **options)
          super(message, code: :payment_error, **options)
        end
      end
    end
  end
end

# Usage
raise BetterService::Errors::Runtime::PaymentError.new(
  "Card declined",
  context: { card_last4: "4242", decline_code: "insufficient_funds" }
)
```
