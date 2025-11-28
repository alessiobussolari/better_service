# Error Codes Reference

## Error Codes Module

All error codes are defined in `BetterService::ErrorCodes`:

```ruby
module BetterService
  module ErrorCodes
    VALIDATION_FAILED = :validation_failed
    UNAUTHORIZED = :unauthorized
    SCHEMA_REQUIRED = :schema_required
    CONFIGURATION_ERROR = :configuration_error
    EXECUTION_ERROR = :execution_error
    RESOURCE_NOT_FOUND = :resource_not_found
    TRANSACTION_ERROR = :transaction_error
    DATABASE_ERROR = :database_error
    WORKFLOW_FAILED = :workflow_failed
    STEP_FAILED = :step_failed
    ROLLBACK_FAILED = :rollback_failed
  end
end
```

## Complete Error Reference

### `:validation_failed`

**Exception:** `Errors::Runtime::ValidationError`

**When:** Parameter validation via Dry::Schema fails during `initialize`

**Context:**
```ruby
{
  service: "Products::CreateService",
  validation_errors: {
    name: ["is missing"],
    price: ["must be a decimal"]
  }
}
```

**Example:**
```ruby
begin
  Products::CreateService.new(user, params: { name: nil })
rescue BetterService::Errors::Runtime::ValidationError => e
  e.code  # => :validation_failed
  e.context[:validation_errors]  # => { name: ["is missing"] }
end
```

---

### `:unauthorized`

**Exception:** `Errors::Runtime::AuthorizationError`

**When:** `authorize_with` block returns false during `call`

**Context:**
```ruby
{
  service: "Products::UpdateService",
  user_id: 123,
  action: "update"
}
```

**Example:**
```ruby
begin
  Products::UpdateService.new(user, params: { id: 1 }).call
rescue BetterService::Errors::Runtime::AuthorizationError => e
  e.code  # => :unauthorized
  e.context[:user_id]  # => 123
end
```

---

### `:schema_required`

**Exception:** `Errors::Configuration::SchemaRequiredError`

**When:** Service class missing `schema` block definition

**Context:**
```ruby
{
  service: "BadService"
}
```

**Example:**
```ruby
class BadService < BetterService::Services::Base
  # Missing schema block
end

begin
  BadService.new(user, params: {})
rescue BetterService::Errors::Configuration::SchemaRequiredError => e
  e.code  # => :schema_required
end
```

---

### `:configuration_error`

**Exception:** `Errors::Configuration::InvalidConfigurationError`

**When:** Invalid service/workflow configuration

**Context:**
```ruby
{
  service: "MyWorkflow",
  message: "No matching branch found and no otherwise block defined"
}
```

**Example:**
```ruby
begin
  workflow.call
rescue BetterService::Errors::Configuration::InvalidConfigurationError => e
  e.code  # => :configuration_error
end
```

---

### `:resource_not_found`

**Exception:** `Errors::Runtime::ResourceNotFoundError`

**When:** `ActiveRecord::RecordNotFound` raised during search phase

**Context:**
```ruby
{
  service: "Products::ShowService",
  model_class: "Product",
  id: 999
}
```

**Original Error:** `ActiveRecord::RecordNotFound`

**Example:**
```ruby
begin
  Products::ShowService.new(user, params: { id: 999 }).call
rescue BetterService::Errors::Runtime::ResourceNotFoundError => e
  e.code  # => :resource_not_found
  e.context[:id]  # => 999
  e.original_error  # => ActiveRecord::RecordNotFound
end
```

---

### `:database_error`

**Exception:** `Errors::Runtime::DatabaseError`

**When:** Database operation fails (validation, save, constraint violation)

**Context:**
```ruby
{
  service: "Products::CreateService",
  operation: "create",
  model_class: "Product"
}
```

**Original Error:** `ActiveRecord::RecordInvalid`, `ActiveRecord::RecordNotSaved`, etc.

**Example:**
```ruby
begin
  Products::CreateService.new(user, params: valid_params).call
rescue BetterService::Errors::Runtime::DatabaseError => e
  e.code  # => :database_error
  e.context[:operation]  # => "create"
  e.original_error  # => ActiveRecord::RecordInvalid
  e.original_error.record.errors.full_messages
end
```

---

### `:transaction_error`

**Exception:** `Errors::Runtime::TransactionError`

**When:** Database transaction fails (deadlock, serialization, explicit rollback)

**Context:**
```ruby
{
  service: "Orders::CreateService",
  operation: "transaction"
}
```

**Original Error:** `ActiveRecord::Rollback`, transaction-related errors

**Example:**
```ruby
begin
  Orders::CreateService.new(user, params: params).call
rescue BetterService::Errors::Runtime::TransactionError => e
  e.code  # => :transaction_error
end
```

---

### `:execution_error`

**Exception:** `Errors::Runtime::ExecutionError`

**When:** Unexpected error during service execution not handled by specific error types

**Context:**
```ruby
{
  service: "MyService",
  phase: "process"  # or "search", "respond"
}
```

**Original Error:** Any `StandardError`

**Example:**
```ruby
begin
  MyService.new(user, params: params).call
rescue BetterService::Errors::Runtime::ExecutionError => e
  e.code  # => :execution_error
  e.context[:phase]  # => "process"
  e.original_error  # => Original exception
end
```

---

### `:workflow_failed`

**Exception:** `Errors::Workflowable::Runtime::WorkflowExecutionError`

**When:** Workflow execution fails

**Context:**
```ruby
{
  workflow: "Order::CheckoutWorkflow",
  steps_executed: [:validate, :create_order],
  branches_taken: ["branch_1:on_1"],
  errors: { ... }
}
```

**Example:**
```ruby
begin
  Order::CheckoutWorkflow.new(user, params: params).call
rescue BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError => e
  e.code  # => :workflow_failed
  e.context[:steps_executed]  # => [:validate, :create_order]
end
```

---

### `:step_failed`

**Exception:** `Errors::Workflowable::Runtime::StepExecutionError`

**When:** A workflow step fails

**Context:**
```ruby
{
  workflow: "Order::CheckoutWorkflow",
  step: :charge_payment,
  steps_executed: [:validate, :create_order]
}
```

**Example:**
```ruby
begin
  workflow.call
rescue BetterService::Errors::Workflowable::Runtime::StepExecutionError => e
  e.code  # => :step_failed
  e.context[:step]  # => :charge_payment
end
```

---

### `:rollback_failed`

**Exception:** `Errors::Workflowable::Runtime::RollbackError`

**When:** Workflow rollback fails (serious - may indicate data inconsistency)

**Context:**
```ruby
{
  workflow: "Order::CheckoutWorkflow",
  step: :create_order,
  executed_steps: [:validate, :create_order, :charge_payment]
}
```

**Example:**
```ruby
begin
  workflow.call
rescue BetterService::Errors::Workflowable::Runtime::RollbackError => e
  e.code  # => :rollback_failed
  e.context[:step]  # => Step whose rollback failed
  Rails.logger.fatal("Rollback failed! Manual intervention required: #{e.to_h}")
end
```

## Error Code Summary Table

| Code | Exception | Phase | Recoverable |
|------|-----------|-------|-------------|
| `:validation_failed` | `ValidationError` | initialize | Yes - fix params |
| `:unauthorized` | `AuthorizationError` | call (early) | Maybe - check permissions |
| `:schema_required` | `SchemaRequiredError` | initialize | No - fix code |
| `:configuration_error` | `InvalidConfigurationError` | varies | No - fix code |
| `:resource_not_found` | `ResourceNotFoundError` | search | Yes - check ID exists |
| `:database_error` | `DatabaseError` | process | Maybe - fix data |
| `:transaction_error` | `TransactionError` | process | Retry possible |
| `:execution_error` | `ExecutionError` | varies | Investigate cause |
| `:workflow_failed` | `WorkflowExecutionError` | workflow | Check step errors |
| `:step_failed` | `StepExecutionError` | workflow | Fix step service |
| `:rollback_failed` | `RollbackError` | workflow | Manual intervention |

## Using Error Codes in Application

```ruby
class ApplicationController < ActionController::Base
  rescue_from BetterService::BetterServiceError do |error|
    case error.code
    when :validation_failed
      render json: { errors: error.context[:validation_errors] }, status: :unprocessable_entity
    when :unauthorized
      render json: { error: "Unauthorized" }, status: :forbidden
    when :resource_not_found
      render json: { error: "Not found" }, status: :not_found
    when :database_error, :transaction_error
      render json: { error: "Database error" }, status: :internal_server_error
    else
      render json: { error: "Internal error" }, status: :internal_server_error
    end
  end
end
```
