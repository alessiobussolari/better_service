# Error Handling

Learn how to handle errors in BetterService.

---

## Error Philosophy

### Pure Exception Pattern

BetterService uses exceptions for error handling.

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

## Error Categories

### Configuration Errors

Programming mistakes caught early.

```ruby
# SchemaRequiredError - Missing schema block
class BadService < BetterService::Services::Base
  # No schema! Raises SchemaRequiredError
end

# NilUserError - User is nil without allow_nil_user
BadService.new(nil, params: {})  # Raises NilUserError
```

--------------------------------

### Runtime Errors

Errors during service execution.

```ruby
# ValidationError - Invalid params (during initialize)
# AuthorizationError - Permission denied (during call)
# ResourceNotFoundError - Record doesn't exist
# ExecutionError - Business logic failure
# DatabaseError - ActiveRecord failures
```

--------------------------------

### Workflow Errors

Errors in workflow execution.

```ruby
# StepExecutionError - A workflow step failed
# RollbackError - Rollback operation failed
# WorkflowExecutionError - General workflow failure
```

--------------------------------

## ValidationError

### When It's Raised

Validation errors occur during initialization.

```ruby
# Raised immediately, not during call
error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
  Product::CreateService.new(user, params: { name: "" })
end

error.code    # => :validation_failed
error.context # => { validation_errors: { name: ["must be filled"] } }
```

--------------------------------

### Handling in Controller

Handle validation errors in controllers.

```ruby
def create
  result = Product::CreateService.new(current_user, params: product_params).call

  if result.success?
    render json: { product: result.resource }, status: :created
  else
    render json: { error: result.message }, status: :unprocessable_entity
  end
rescue BetterService::Errors::Runtime::ValidationError => e
  render json: {
    error: "Validation failed",
    errors: e.context[:validation_errors]
  }, status: :unprocessable_entity
end
```

--------------------------------

## AuthorizationError

### When It's Raised

Authorization errors when authorize_with returns false.

```ruby
result = Product::UpdateService.new(non_owner, params: { id: 1 }).call

result.success?          # => false
result.meta[:error_code] # => :unauthorized
```

--------------------------------

### Handling Authorization

Handle authorization failures.

```ruby
def update
  result = Product::UpdateService.new(current_user, params: params).call

  if result.success?
    render json: { product: result.resource }
  elsif result.meta[:error_code] == :unauthorized
    render json: { error: "You don't have permission" }, status: :forbidden
  else
    render json: { error: result.message }, status: :unprocessable_entity
  end
end
```

--------------------------------

## ResourceNotFoundError

### Raising in Services

Raise when a record isn't found.

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

Handle not found errors.

```ruby
def show
  result = Product::ShowService.new(current_user, params: { id: params[:id] }).call

  if result.success?
    render json: { product: result.resource }
  elsif result.meta[:error_code] == :resource_not_found
    render json: { error: "Product not found" }, status: :not_found
  else
    render json: { error: result.message }, status: :unprocessable_entity
  end
end
```

--------------------------------

## ExecutionError

### Raising Business Errors

Raise for business rule violations.

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
      "Cannot modify product with orders",
      context: { id: product.id, orders_count: product.orders.count }
    )
  end

  product_repository.update!(product, published: true)
  { resource: product.reload }
end
```

--------------------------------

## DatabaseError

### Wrapping ActiveRecord Errors

Wrap database exceptions.

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

## Error Information

### Accessing Error Details

All errors provide rich information.

```ruby
begin
  service.call
rescue BetterService::BetterServiceError => e
  e.code           # Symbol: :validation_failed, :unauthorized, etc.
  e.message        # Human-readable message
  e.context        # Hash with error details
  e.original_error # Original exception (if wrapped)
  e.timestamp      # When error occurred
  e.to_h           # Full hash representation
end
```

--------------------------------

## Global Error Handler

### ApplicationController Handler

Centralized error handling.

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

Error handling for API controllers.

```ruby
class Api::V1::BaseController < ActionController::API
  rescue_from BetterService::Errors::Runtime::ValidationError do |e|
    render json: {
      error: { code: e.code, message: "Validation failed", details: e.context[:validation_errors] }
    }, status: :unprocessable_entity
  end

  rescue_from BetterService::Errors::Runtime::AuthorizationError do |e|
    render json: {
      error: { code: e.code, message: "Forbidden" }
    }, status: :forbidden
  end

  rescue_from BetterService::Errors::Runtime::ResourceNotFoundError do |e|
    render json: {
      error: { code: e.code, message: "Not found", resource: e.context[:model_class] }
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

## Error Tracking

### Sentry Integration

Send errors to Sentry.

```ruby
rescue BetterService::BetterServiceError => e
  Sentry.capture_exception(e, extra: {
    code: e.code,
    context: e.context,
    service: e.context[:service]
  })
  raise
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

## Best Practices

### Error Handling Guidelines

Follow these guidelines.

```ruby
# 1. Always include context in errors
raise ResourceNotFoundError.new(
  "Product not found",
  context: { id: params[:id], model_class: "Product" }  # Rich context
)

# 2. Use appropriate error types
# ResourceNotFoundError for missing records
# ExecutionError for business logic failures
# DatabaseError for database issues

# 3. Wrap original exceptions
rescue ActiveRecord::RecordInvalid => e
  raise DatabaseError.new("Failed", context: {...}, original_error: e)
end

# 4. Log errors with context
Rails.logger.error(error.to_h)

# 5. Handle errors at the appropriate level
# Service: Raise specific errors
# Controller: Catch and format response
# Application: Global fallback handler
```

--------------------------------
