# Error Handling

Master exception management in BetterService.

---

## Error Philosophy

### Pure Exception Pattern

BetterService uses exceptions for all errors.

```ruby
# Errors raise exceptions with rich context
begin
  result = Product::CreateService.new(user, params: invalid_params).call
rescue BetterService::Errors::Runtime::ValidationError => e
  e.code      # => :validation_failed
  e.message   # => "Validation failed"
  e.context   # => { validation_errors: { name: ["is missing"] } }
end
```

--------------------------------

## Error Hierarchy

### Exception Classes

All errors inherit from BetterServiceError.

```ruby
BetterService::BetterServiceError
├── Errors::Configuration::*           # Programming errors
│   ├── SchemaRequiredError           # Missing schema block
│   ├── NilUserError                  # User is nil
│   ├── InvalidSchemaError            # Invalid schema syntax
│   └── InvalidConfigurationError     # Bad configuration
│
├── Errors::Runtime::*                 # Execution errors
│   ├── ValidationError               # Schema validation failed
│   ├── AuthorizationError            # Permission denied
│   ├── ResourceNotFoundError         # Record not found
│   ├── DatabaseError                 # Database operation failed
│   ├── TransactionError              # Transaction rollback
│   └── ExecutionError                # General execution error
│
└── Errors::Workflowable::Runtime::*   # Workflow errors
    ├── WorkflowExecutionError        # Workflow failed
    ├── StepExecutionError            # Step failed
    └── RollbackError                 # Rollback failed
```

--------------------------------

## Error Information

### Accessing Error Details

All errors provide rich information.

```ruby
begin
  service.call
rescue BetterService::BetterServiceError => e
  e.code           # Symbol: :validation_failed, :unauthorized
  e.message        # Human-readable message
  e.context        # Hash with error details
  e.original_error # Original exception (if wrapped)
  e.timestamp      # When error occurred
  e.to_h           # Full hash representation
end
```

--------------------------------

## ValidationError

### When It Occurs

Validation errors are raised during initialize.

```ruby
# Raised during initialize, NOT during call
error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
  Product::CreateService.new(user, params: { name: "" })  # Fails here
end

error.code                            # => :validation_failed
error.context[:validation_errors]     # => { name: ["must be filled"] }
```

--------------------------------

### Handling Validation Errors

Handle validation errors in controllers.

```ruby
def create
  result = Product::CreateService.new(current_user, params: product_params).call
  render json: { product: result.resource }, status: :created
rescue BetterService::Errors::Runtime::ValidationError => e
  render json: {
    error: "Validation failed",
    errors: e.context[:validation_errors]
  }, status: :unprocessable_entity
end
```

--------------------------------

## AuthorizationError

### When It Occurs

Authorization errors occur during call when authorize_with returns false.

```ruby
# Returns failure result (not exception by default)
result = Product::UpdateService.new(non_owner, params: { id: 1 }).call

result.success?          # => false
result.meta[:error_code] # => :unauthorized
```

--------------------------------

### Checking Authorization Failure

Handle unauthorized results.

```ruby
def update
  result = Product::UpdateService.new(current_user, params: update_params).call

  if result.success?
    render json: { product: result.resource }
  elsif result.meta[:error_code] == :unauthorized
    render json: { error: "Permission denied" }, status: :forbidden
  else
    render json: { error: result.message }, status: :unprocessable_entity
  end
end
```

--------------------------------

## ResourceNotFoundError

### Raising Not Found

Raise when records aren't found.

```ruby
search_with do
  product = product_repository.find(params[:id])
  { resource: product }
rescue ActiveRecord::RecordNotFound
  raise BetterService::Errors::Runtime::ResourceNotFoundError.new(
    "Product not found",
    context: {
      id: params[:id],
      model_class: "Product"
    }
  )
end
```

--------------------------------

### Handling Not Found

Handle in controllers.

```ruby
def show
  result = Product::ShowService.new(current_user, params: { id: params[:id] }).call

  if result.success?
    render json: { product: result.resource }
  elsif result.meta[:error_code] == :resource_not_found
    render json: { error: "Product not found" }, status: :not_found
  end
rescue BetterService::Errors::Runtime::ResourceNotFoundError => e
  render json: {
    error: "Not found",
    details: e.context
  }, status: :not_found
end
```

--------------------------------

## ExecutionError

### Raising Business Logic Errors

Use for business rule violations.

```ruby
process_with do |data|
  product = data[:resource]

  if product.published?
    raise BetterService::Errors::Runtime::ExecutionError.new(
      "Product is already published",
      context: { id: product.id, status: product.status }
    )
  end

  if product.orders.any?
    raise BetterService::Errors::Runtime::ExecutionError.new(
      "Cannot delete product with existing orders",
      context: { orders_count: product.orders.count }
    )
  end

  product_repository.update!(product, published: true)
  { resource: product.reload }
end
```

--------------------------------

## DatabaseError

### Wrapping ActiveRecord Errors

Wrap database exceptions with context.

```ruby
process_with do |data|
  product = product_repository.create!(params)
  { resource: product }
rescue ActiveRecord::RecordInvalid => e
  raise BetterService::Errors::Runtime::DatabaseError.new(
    "Failed to create product",
    context: { errors: e.record.errors.to_hash },
    original_error: e
  )
rescue ActiveRecord::RecordNotUnique => e
  raise BetterService::Errors::Runtime::DatabaseError.new(
    "Product with this name already exists",
    context: { name: params[:name] },
    original_error: e
  )
end
```

--------------------------------

## Global Error Handler

### ApplicationController Handler

Centralize error handling.

```ruby
class ApplicationController < ActionController::Base
  rescue_from BetterService::BetterServiceError, with: :handle_service_error

  private

  def handle_service_error(error)
    Rails.logger.error({
      error_class: error.class.name,
      code: error.code,
      message: error.message,
      context: error.context
    }.to_json)

    case error.code
    when :validation_failed
      render json: {
        error: "Validation failed",
        errors: error.context[:validation_errors]
      }, status: :unprocessable_entity
    when :unauthorized
      render json: { error: "Forbidden" }, status: :forbidden
    when :resource_not_found
      render json: { error: "Not found" }, status: :not_found
    else
      render json: { error: "Internal error" }, status: :internal_server_error
    end
  end
end
```

--------------------------------

## API Error Handler

### JSON API Controller

Error handling for APIs.

```ruby
class Api::V1::BaseController < ActionController::API
  rescue_from BetterService::Errors::Runtime::ValidationError do |e|
    render json: {
      error: {
        code: e.code,
        message: "Validation failed",
        details: e.context[:validation_errors]
      }
    }, status: :unprocessable_entity
  end

  rescue_from BetterService::Errors::Runtime::AuthorizationError do |e|
    render json: {
      error: { code: e.code, message: "Forbidden" }
    }, status: :forbidden
  end

  rescue_from BetterService::Errors::Runtime::ResourceNotFoundError do |e|
    render json: {
      error: {
        code: e.code,
        message: "Not found",
        resource: e.context[:model_class]
      }
    }, status: :not_found
  end

  rescue_from BetterService::BetterServiceError do |e|
    Rails.logger.error(e.to_h)
    render json: {
      error: { code: e.code, message: "Internal error" }
    }, status: :internal_server_error
  end
end
```

--------------------------------

## Workflow Errors

### Handling Workflow Failures

Handle workflow-specific errors.

```ruby
begin
  result = Order::CheckoutWorkflow.new(user, params: params).call

  if result[:success]
    render json: { order: result[:context].create_order }
  end
rescue BetterService::Errors::Workflowable::Runtime::StepExecutionError => e
  Rails.logger.error "Step '#{e.context[:step]}' failed: #{e.message}"
  render json: {
    error: "Checkout failed at #{e.context[:step]}",
    details: e.context
  }, status: :unprocessable_entity
rescue BetterService::Errors::Workflowable::Runtime::RollbackError => e
  Rails.logger.error "Rollback failed: #{e.message}"
  # Alert operations team - manual intervention needed
  render json: { error: "System error" }, status: :internal_server_error
end
```

--------------------------------

## Error Tracking Integration

### Sentry Integration

Send errors to Sentry.

```ruby
rescue BetterService::BetterServiceError => e
  Sentry.capture_exception(e, extra: {
    code: e.code,
    context: e.context,
    service: e.context[:service]
  })
  raise  # Re-raise for controller handling
end
```

--------------------------------

### Honeybadger Integration

Send errors to Honeybadger.

```ruby
rescue BetterService::BetterServiceError => e
  Honeybadger.notify(e, context: {
    error_code: e.code,
    service_context: e.context
  })
  raise
end
```

--------------------------------

## Testing Errors

### Test Exception Raising

Verify errors are raised correctly.

```ruby
test "raises ValidationError for missing name" do
  error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
    Product::CreateService.new(@user, params: { price: 99.99 })
  end

  assert_equal :validation_failed, error.code
  assert error.context[:validation_errors].key?(:name)
end

test "raises ResourceNotFoundError for invalid id" do
  error = assert_raises(BetterService::Errors::Runtime::ResourceNotFoundError) do
    Product::ShowService.new(@user, params: { id: 999999 }).call
  end

  assert_equal :resource_not_found, error.code
  assert_equal 999999, error.context[:id]
end
```

--------------------------------

### Test Authorization Failure

Verify authorization returns failure.

```ruby
test "returns unauthorized for non-owner" do
  other_user = users(:other)
  product = products(:owned_by_seller)

  result = Product::UpdateService.new(
    other_user,
    params: { id: product.id, name: "Hacked" }
  ).call

  refute result.success?
  assert_equal :unauthorized, result.meta[:error_code]
end
```

--------------------------------

## Best Practices

### Error Handling Guidelines

Follow these patterns.

```ruby
# 1. Always include context in errors
raise ResourceNotFoundError.new(
  "Product not found",
  context: { id: params[:id], model_class: "Product" }
)

# 2. Use appropriate error types
# ResourceNotFoundError - missing records
# ExecutionError - business logic failures
# DatabaseError - database issues

# 3. Wrap original exceptions
rescue ActiveRecord::RecordInvalid => e
  raise DatabaseError.new("Failed", context: {...}, original_error: e)
end

# 4. Log errors with context
Rails.logger.error(error.to_h)

# 5. Handle at appropriate level
# Service: Raise specific errors
# Controller: Catch and format response
# Application: Global fallback handler
```

--------------------------------

## Next Steps

### Continue Learning

What to learn next.

```ruby
# Now that you understand error handling:

# 1. Test your services
#    → guide/08-testing.md

# 2. See complete examples
#    → guide/09-real-world-example.md
```

--------------------------------
