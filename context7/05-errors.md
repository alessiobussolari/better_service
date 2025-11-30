# Error Handling

BetterService uses a pure exception pattern with rich context information.

---

## Exception Hierarchy

### Error Class Structure

All exceptions inherit from `BetterServiceError`.

```ruby
# BetterServiceError (base)
# ├── Configuration Errors (programming mistakes)
# │   ├── SchemaRequiredError      # Missing schema definition
# │   ├── NilUserError             # User is nil when required
# │   ├── InvalidSchemaError       # Invalid schema syntax
# │   └── InvalidConfigurationError # Invalid config settings
# │
# ├── Runtime Errors (execution failures)
# │   ├── ValidationError          # Parameter validation failed
# │   ├── AuthorizationError       # User not authorized
# │   ├── ResourceNotFoundError    # Record not found
# │   ├── DatabaseError            # Database operation failed
# │   ├── TransactionError         # Transaction rollback
# │   └── ExecutionError           # Unexpected error
# │
# └── Workflowable Errors (workflow execution)
#     ├── WorkflowExecutionError   # Workflow failed
#     ├── StepExecutionError       # Step failed
#     └── RollbackError            # Rollback failed
```

--------------------------------

## Error Information

### Exception Methods

All exceptions provide these methods.

```ruby
error.code           # Symbol (:validation_failed, :unauthorized, etc.)
error.message        # Human-readable error message
error.context        # Hash with service-specific data
error.original_error # Original exception if wrapping another error
error.timestamp      # When the error occurred
error.to_h           # Structured hash representation
error.detailed_message # Extended message with context
```

--------------------------------

## Error Codes Reference

### Error Code Table

Error codes and when they are raised.

```ruby
# Code                   | Error Class              | When Raised
# -----------------------|--------------------------|--------------------------------
# :schema_required       | SchemaRequiredError      | No schema block defined
# :nil_user              | NilUserError             | User is nil without allow_nil_user
# :invalid_schema        | InvalidSchemaError       | Schema syntax error
# :configuration_error   | InvalidConfigurationError| Invalid config
# :validation_failed     | ValidationError          | Schema validation fails
# :unauthorized          | AuthorizationError       | authorize_with returns false
# :resource_not_found    | ResourceNotFoundError    | Record not found
# :database_error        | DatabaseError            | ActiveRecord failure
# :transaction_error     | TransactionError         | Transaction rollback
# :execution_error       | ExecutionError           | Unexpected error
# :workflow_failed       | WorkflowExecutionError   | Workflow execution failed
# :step_failed           | StepExecutionError       | Workflow step failed
# :rollback_failed       | RollbackError            | Rollback operation failed
```

--------------------------------

## Raising ResourceNotFoundError

### Resource Not Found

Raise when a record cannot be found.

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

## Raising DatabaseError

### Database Operation Failed

Raise when a database operation fails.

```ruby
process_with do |_data|
  product = product_repository.create!(params)
  { resource: product }
rescue ActiveRecord::RecordInvalid => e
  raise BetterService::Errors::Runtime::DatabaseError.new(
    "Failed to create product",
    context: { errors: e.record.errors.to_hash },
    original_error: e
  )
end
```

--------------------------------

## Raising ExecutionError

### Business Logic Error

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

  product_repository.update!(product, published: true)
  { resource: product.reload }
end
```

--------------------------------

## Controller Error Handling

### Basic Error Handling

Handle service errors in controllers.

```ruby
class ProductsController < ApplicationController
  def create
    result = Product::CreateService.new(current_user, params: product_params).call

    if result.success?
      render json: { product: result.resource }, status: :created
    else
      render json: { error: result.message, code: result.meta[:error_code] },
             status: error_status(result.meta[:error_code])
    end
  rescue BetterService::Errors::Runtime::ValidationError => e
    render json: { errors: e.context[:validation_errors] }, status: :unprocessable_entity
  rescue BetterService::Errors::Runtime::AuthorizationError => e
    render json: { error: "Not authorized" }, status: :forbidden
  rescue BetterService::Errors::Runtime::ResourceNotFoundError => e
    render json: { error: e.message }, status: :not_found
  rescue BetterService::Errors::Runtime::DatabaseError => e
    Rails.logger.error("Database error: #{e.to_h}")
    render json: { error: "Could not save record" }, status: :internal_server_error
  end

  private

  def error_status(code)
    case code
    when :unauthorized then :forbidden
    when :resource_not_found then :not_found
    when :validation_failed then :unprocessable_entity
    else :unprocessable_entity
    end
  end
end
```

--------------------------------

## Global Error Handler

### ApplicationController Handler

Centralized error handling for all controllers.

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

--------------------------------

## API Error Response

### JSON API Error Handler

Error handling for API controllers.

```ruby
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

--------------------------------

## Error Tracking

### Sentry Integration

Send errors to Sentry for monitoring.

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

## Testing Errors

### Testing ValidationError

Test that validation errors are raised correctly.

```ruby
test "raises ValidationError for missing name" do
  error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
    Product::CreateService.new(users(:admin), params: { price: 10.00 })
  end

  assert_equal :validation_failed, error.code
  assert error.context[:validation_errors].key?(:name)
  assert_includes error.context[:validation_errors][:name], "is missing"
end
```

--------------------------------

### Testing AuthorizationError

Test authorization failures.

```ruby
test "returns unauthorized for non-owner" do
  product = products(:other_user_product)
  user = users(:regular_user)

  result = Product::UpdateService.new(user, params: { id: product.id, name: "New" }).call

  refute result.success?
  assert_equal :unauthorized, result.meta[:error_code]
end
```

--------------------------------

### Testing ResourceNotFoundError

Test resource not found errors.

```ruby
test "raises ResourceNotFoundError for non-existent product" do
  error = assert_raises(BetterService::Errors::Runtime::ResourceNotFoundError) do
    Product::ShowService.new(users(:admin), params: { id: 999999 }).call
  end

  assert_equal :resource_not_found, error.code
  assert_equal 999999, error.context[:id]
  assert_equal "Product", error.context[:model_class]
end
```

--------------------------------

### Testing Workflow Errors

Test workflow step failures.

```ruby
test "raises StepExecutionError when step fails" do
  error = assert_raises(BetterService::Errors::Workflowable::Runtime::StepExecutionError) do
    FailingWorkflow.new(user, params: { id: 1 }).call
  end

  assert_equal :step_failed, error.code
  assert_equal :failing_step, error.context[:step]
end
```

--------------------------------
