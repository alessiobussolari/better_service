# Error Handling Guide

BetterService uses a **Pure Exception Pattern** where all errors raise exceptions with rich context information. This guide covers the complete error handling system.

## Table of Contents

- [Error Philosophy](#error-philosophy)
- [Exception Hierarchy](#exception-hierarchy)
- [Error Types](#error-types)
- [Handling Errors](#handling-errors)
- [Error Context](#error-context)
- [Controller Patterns](#controller-patterns)
- [Testing Errors](#testing-errors)
- [Best Practices](#best-practices)

---

## Error Philosophy

### Pure Exception Pattern

BetterService **always raises exceptions** on errors. There are no success/failure flags or error hashes.

**Why?**
- **Consistent behavior** across all environments
- **Fail-fast** - errors can't be silently ignored
- **Rich context** - exceptions carry detailed debugging info
- **Stack traces** - full execution path preserved
- **Standard Ruby patterns** - works with rescue/ensure

**What this means:**
```ruby
# ✅ This is how BetterService works
begin
  result = MyService.new(user, params: params).call
  # If we get here, it succeeded
  product = result[:resource]
rescue BetterService::Errors::Runtime::ValidationError => e
  # Handle validation failure
end

# ❌ This is NOT how BetterService works (no success flag)
result = MyService.new(user, params: params).call
if result[:success]  # ← This always returns true if call completed
  # ...
end
```

---

## Exception Hierarchy

All BetterService exceptions inherit from `BetterService::BetterServiceError`:

```
BetterServiceError (base)
├── Configuration Errors (programming errors)
│   ├── Errors::Configuration::SchemaRequiredError
│   ├── Errors::Configuration::InvalidSchemaError
│   ├── Errors::Configuration::InvalidConfigurationError
│   └── Errors::Configuration::NilUserError
│
├── Runtime Errors (execution errors)
│   ├── Errors::Runtime::ValidationError
│   ├── Errors::Runtime::AuthorizationError
│   ├── Errors::Runtime::ResourceNotFoundError
│   ├── Errors::Runtime::DatabaseError
│   ├── Errors::Runtime::TransactionError
│   └── Errors::Runtime::ExecutionError
│
└── Workflowable Errors
    ├── Configuration
    │   ├── Errors::Workflowable::Configuration::WorkflowConfigurationError
    │   ├── Errors::Workflowable::Configuration::StepNotFoundError
    │   ├── Errors::Workflowable::Configuration::InvalidStepError
    │   └── Errors::Workflowable::Configuration::DuplicateStepError
    └── Runtime
        ├── Errors::Workflowable::Runtime::WorkflowExecutionError
        ├── Errors::Workflowable::Runtime::StepExecutionError
        └── Errors::Workflowable::Runtime::RollbackError
```

---

## Error Types

### Configuration Errors

**When**: During service class definition or initialization
**Cause**: Programming errors in service code

#### SchemaRequiredError

Service missing mandatory `schema` block.

```ruby
class MyService < BetterService::Base
  # Missing schema block!
end

MyService.new(user, params: {})
# => BetterService::Errors::Configuration::SchemaRequiredError
```

**Fix**: Always define a schema, even if empty:
```ruby
schema do
  # Empty schema - no params required
end
```

---

#### NilUserError

User is `nil` when required.

```ruby
MyService.new(nil, params: {})
# => BetterService::Errors::Configuration::NilUserError
```

**Fix**: Pass valid user or allow nil:
```ruby
class MyService < BetterService::Base
  self._allow_nil_user = true
end
```

---

#### InvalidSchemaError

Invalid Dry::Schema syntax.

```ruby
schema do
  required(:email).filled(:invalid_type)  # Invalid type
end
# => BetterService::Errors::Configuration::InvalidSchemaError
```

**Fix**: Use valid Dry::Schema types and predicates.

---

### Runtime Errors

**When**: During service execution
**Cause**: Invalid inputs, permissions, or business logic failures

#### ValidationError

Parameter validation failed against schema.

**When raised**: During service `initialize` (before `call`)

```ruby
class Product::CreateService < BetterService::Services::CreateService
  schema do
    required(:name).filled(:string)
    required(:price).filled(:decimal, gt?: 0)
  end
end

# Raises ValidationError immediately
service = Product::CreateService.new(user, params: {
  name: "",      # Invalid: must be filled
  price: -10     # Invalid: must be > 0
})
# => BetterService::Errors::Runtime::ValidationError
```

**Error details:**
```ruby
begin
  Product::CreateService.new(user, params: invalid_params)
rescue BetterService::Errors::Runtime::ValidationError => e
  e.message
  # => "Validation failed"

  e.code
  # => :validation_failed

  e.context[:validation_errors]
  # => {
  #   name: ["must be filled"],
  #   price: ["must be greater than 0"]
  # }

  e.context[:service]
  # => "Product::CreateService"

  e.context[:params]
  # => { name: "", price: -10 }
end
```

---

#### AuthorizationError

User not authorized to perform action.

**When raised**: During `call`, before search phase

```ruby
class Product::DestroyService < BetterService::Services::DestroyService
  authorize_with do
    user.admin? || Product.find(params[:id]).user_id == user.id
  end
end

# User is not admin and doesn't own product
Product::DestroyService.new(user, params: { id: 123 }).call
# => BetterService::Errors::Runtime::AuthorizationError
```

**Error details:**
```ruby
begin
  service.call
rescue BetterService::Errors::Runtime::AuthorizationError => e
  e.message
  # => "Not authorized to perform this action"

  e.code
  # => :unauthorized

  e.context[:service]
  # => "Product::DestroyService"

  e.context[:user]
  # => "user_123" or "nil"
end
```

---

#### ResourceNotFoundError

ActiveRecord record not found.

**When raised**: During `search` or `process` phase

```ruby
search_with do
  { product: user.products.find(params[:id]) }
end

Product::ShowService.new(user, params: { id: 99999 }).call
# => BetterService::Errors::Runtime::ResourceNotFoundError
```

**Error details:**
```ruby
begin
  service.call
rescue BetterService::Errors::Runtime::ResourceNotFoundError => e
  e.message
  # => "Resource not found: Couldn't find Product with 'id'=99999"

  e.code
  # => :resource_not_found

  e.original_error
  # => <ActiveRecord::RecordNotFound instance>

  e.context[:service]
  # => "Product::ShowService"
end
```

---

#### DatabaseError

Database constraint violations or ActiveRecord validation failures.

**When raised**: During `process` phase

```ruby
process_with do |data|
  Product.create!(
    name: nil,  # Violates NOT NULL constraint
    sku: "DUPLICATE"  # Violates uniqueness constraint
  )
end

service.call
# => BetterService::Errors::Runtime::DatabaseError
```

**Error details:**
```ruby
begin
  service.call
rescue BetterService::Errors::Runtime::DatabaseError => e
  e.message
  # => "Database error: Validation failed: Name can't be blank"

  e.code
  # => :database_error

  e.original_error
  # => <ActiveRecord::RecordInvalid instance>

  e.context[:service]
  # => "Product::CreateService"
end
```

**Handles:**
- `ActiveRecord::RecordInvalid` - Model validation failed
- `ActiveRecord::RecordNotSaved` - Save failed
- `ActiveRecord::RecordNotDestroyed` - Destroy failed
- `ActiveRecord::InvalidForeignKey` - FK constraint violated
- `ActiveRecord::NotNullViolation` - NULL constraint violated
- `ActiveRecord::RecordNotUnique` - Uniqueness violated

---

#### TransactionError

Database transaction rolled back.

**When raised**: When transaction fails in services with `with_transaction true`

```ruby
class Order::CreateService < BetterService::Services::CreateService
  # Transactions enabled by default

  process_with do |data|
    order = Order.create!(params)

    # This fails, causing rollback
    raise "Payment processor unavailable"
  end
end

service.call
# => BetterService::Errors::Runtime::TransactionError
```

---

#### ExecutionError

Unexpected error during service execution.

**When raised**: When an unhandled exception occurs

```ruby
process_with do |data|
  # Unexpected error
  nil.do_something
end

service.call
# => BetterService::Errors::Runtime::ExecutionError
```

**Error details:**
```ruby
begin
  service.call
rescue BetterService::Errors::Runtime::ExecutionError => e
  e.message
  # => "Service execution failed: undefined method 'do_something' for nil"

  e.code
  # => :execution_failed

  e.original_error
  # => <NoMethodError instance>

  e.context[:service]
  # => "MyService"
end
```

---

### Workflow Errors

See [Workflows Documentation](../workflows/01_workflows_introduction.md) for workflow-specific errors.

---

## Handling Errors

### Basic Pattern

```ruby
begin
  result = MyService.new(current_user, params: params).call
  # Success - use result
  resource = result[:resource]

rescue BetterService::Errors::Runtime::ValidationError => e
  # Invalid params
  errors = e.context[:validation_errors]

rescue BetterService::Errors::Runtime::AuthorizationError => e
  # Not authorized
  message = e.message

rescue BetterService::Errors::Runtime::ResourceNotFoundError => e
  # Record not found
  message = e.message

rescue BetterService::Errors::Runtime::DatabaseError => e
  # DB constraint or validation
  original = e.original_error

rescue BetterService::BetterServiceError => e
  # Catch-all for any BetterService error
  Rails.logger.error("Service error: #{e.to_h}")
end
```

---

### Order Matters

Rescue specific errors before generic ones:

```ruby
# ✅ Correct order
begin
  service.call
rescue BetterService::Errors::Runtime::ValidationError => e
  # Handle validation error
rescue BetterService::BetterServiceError => e
  # Handle any other BetterService error
end

# ❌ Wrong order - ValidationError never caught
begin
  service.call
rescue BetterService::BetterServiceError => e
  # This catches ValidationError too!
rescue BetterService::Errors::Runtime::ValidationError => e
  # Never reached
end
```

---

## Error Context

All errors provide rich context via `#context`:

```ruby
begin
  service.call
rescue BetterService::BetterServiceError => e
  e.context
  # => {
  #   service: "Product::CreateService",
  #   params: { name: "...", price: 99 },
  #   user: "user_123",
  #   validation_errors: { name: ["..."] },  # If ValidationError
  #   ... (error-specific context)
  # }
end
```

### Common Context Keys

| Key | Present In | Description |
|-----|------------|-------------|
| `:service` | All errors | Service class name |
| `:params` | Most errors | Service params |
| `:user` | Most errors | User ID or "nil" |
| `:validation_errors` | ValidationError | Hash of field errors |
| `:workflow` | Workflow errors | Workflow name |
| `:step` | Step errors | Step name |

---

### Error Methods

All `BetterServiceError` exceptions provide:

```ruby
error.message           # Human-readable message
error.code              # Symbol code (:validation_failed, :unauthorized, etc.)
error.context           # Hash with error context
error.original_error    # Original exception (if wrapping)
error.timestamp         # When error occurred
error.to_h              # Full structured hash
error.detailed_message  # Extended message with context
error.backtrace         # Enhanced backtrace
```

**Example:**
```ruby
begin
  service.call
rescue BetterService::BetterServiceError => e
  # Structured logging
  Rails.logger.error(e.to_h.to_json)

  # => {
  #   "error_class": "BetterService::Errors::Runtime::ValidationError",
  #   "message": "Validation failed",
  #   "code": "validation_failed",
  #   "timestamp": "2025-11-11T10:30:00Z",
  #   "context": { "service": "MyService", ... },
  #   "original_error": { "class": "StandardError", ... },
  #   "backtrace": [...]
  # }
end
```

---

## Controller Patterns

### Basic Controller Error Handling

```ruby
class ProductsController < ApplicationController
  def create
    result = Product::CreateService.new(current_user, params: product_params).call
    render json: result, status: :created

  rescue BetterService::Errors::Runtime::ValidationError => e
    render json: {
      error: e.message,
      errors: e.context[:validation_errors]
    }, status: :unprocessable_entity

  rescue BetterService::Errors::Runtime::AuthorizationError => e
    render json: { error: e.message }, status: :forbidden

  rescue BetterService::Errors::Runtime::ResourceNotFoundError => e
    render json: { error: "Resource not found" }, status: :not_found

  rescue BetterService::Errors::Runtime::DatabaseError => e
    render json: { error: e.message }, status: :unprocessable_entity

  rescue BetterService::BetterServiceError => e
    Rails.logger.error("Service error: #{e.to_h}")
    render json: { error: "An error occurred" }, status: :internal_server_error
  end

  private

  def product_params
    params.require(:product).permit(:name, :price, :description)
  end
end
```

---

### Centralized Error Handler

Use `rescue_from` in `ApplicationController`:

```ruby
class ApplicationController < ActionController::API
  rescue_from BetterService::Errors::Runtime::ValidationError, with: :handle_validation_error
  rescue_from BetterService::Errors::Runtime::AuthorizationError, with: :handle_authorization_error
  rescue_from BetterService::Errors::Runtime::ResourceNotFoundError, with: :handle_not_found
  rescue_from BetterService::Errors::Runtime::DatabaseError, with: :handle_database_error
  rescue_from BetterService::BetterServiceError, with: :handle_service_error

  private

  def handle_validation_error(error)
    render json: {
      error: error.message,
      errors: error.context[:validation_errors]
    }, status: :unprocessable_entity
  end

  def handle_authorization_error(error)
    render json: { error: error.message }, status: :forbidden
  end

  def handle_not_found(error)
    render json: { error: "Resource not found" }, status: :not_found
  end

  def handle_database_error(error)
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def handle_service_error(error)
    Rails.logger.error("Service error: #{error.to_h}")

    # In development, show full error
    if Rails.env.development?
      render json: {
        error: error.message,
        details: error.context,
        backtrace: error.backtrace[0..10]
      }, status: :internal_server_error
    else
      # In production, generic message
      render json: { error: "An error occurred" }, status: :internal_server_error
    end
  end
end
```

Now all controllers automatically handle service errors:

```ruby
class ProductsController < ApplicationController
  def create
    result = Product::CreateService.new(current_user, params: product_params).call
    render json: result, status: :created
  end
  # Errors automatically handled by ApplicationController
end
```

---

## Testing Errors

### Testing Validation Errors

```ruby
test "validates required params" do
  error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
    Product::CreateService.new(user, params: { name: "", price: -10 })
  end

  assert_equal :validation_failed, error.code
  assert error.context[:validation_errors].key?(:name)
  assert error.context[:validation_errors].key?(:price)
end
```

---

### Testing Authorization Errors

```ruby
test "checks authorization" do
  other_user = users(:other)

  error = assert_raises(BetterService::Errors::Runtime::AuthorizationError) do
    Product::UpdateService.new(other_user, params: { id: product.id, name: "Updated" }).call
  end

  assert_equal :unauthorized, error.code
  assert_equal "Product::UpdateService", error.context[:service]
end
```

---

### Testing Database Errors

```ruby
test "handles database errors" do
  # Create product with duplicate SKU
  Product.create!(name: "Original", sku: "ABC123")

  error = assert_raises(BetterService::Errors::Runtime::DatabaseError) do
    Product::CreateService.new(user, params: { name: "Duplicate", sku: "ABC123" }).call
  end

  assert_equal :database_error, error.code
  assert_instance_of ActiveRecord::RecordInvalid, error.original_error
end
```

---

## Best Practices

### 1. Always Rescue Specific Errors First

```ruby
# ✅ Good
rescue ValidationError => e
  # ...
rescue BetterServiceError => e
  # ...

# ❌ Bad - ValidationError never caught
rescue BetterServiceError => e
  # ...
rescue ValidationError => e
  # ...
```

---

### 2. Use Context for Debugging

```ruby
rescue BetterServiceError => e
  Rails.logger.error({
    message: e.message,
    service: e.context[:service],
    params: e.context[:params],
    user: e.context[:user],
    backtrace: e.backtrace[0..10]
  }.to_json)
end
```

---

### 3. Don't Swallow Errors

```ruby
# ❌ Bad - error lost
begin
  service.call
rescue BetterServiceError
  # Do nothing
end

# ✅ Good - log or re-raise
begin
  service.call
rescue BetterServiceError => e
  Rails.logger.error(e.to_h)
  raise  # Re-raise if you can't handle it
end
```

---

### 4. Use Centralized Error Handling

Prefer `rescue_from` in `ApplicationController` over per-action rescues.

---

### 5. Test Error Scenarios

Always test that your services raise the correct errors:

```ruby
test "raises validation error for invalid params" do
  assert_raises(ValidationError) do
    MyService.new(user, params: invalid_params)
  end
end
```

---

## Next Steps

- **[Configuration](../start/configuration.md)** - Configure error reporting
- **[Testing Guide](../testing.md)** - Comprehensive testing patterns
- **[Workflows](../workflows/01_workflows_introduction.md)** - Workflow error handling

---

**See Also:**
- [Getting Started](../start/getting-started.md)
- [Service Types](../services/01_services_structure.md)
- [Concerns Reference](../concerns-reference.md)
