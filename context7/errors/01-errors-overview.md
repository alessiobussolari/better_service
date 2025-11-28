# Error Handling Overview

BetterService uses a **Pure Exception Pattern** where all errors raise exceptions with rich context information.

## Base Exception Class

All exceptions inherit from `BetterService::BetterServiceError`:

```ruby
begin
  service.call
rescue BetterService::BetterServiceError => e
  e.code           # Symbol: :validation_failed, :unauthorized, etc.
  e.message        # Human-readable message
  e.context        # Hash with service-specific details
  e.original_error # Wrapped exception (if any)
  e.timestamp      # When the error occurred
  e.to_h           # Structured hash representation
  e.detailed_message # Extended message with context
end
```

## Error Hierarchy

```
BetterServiceError (base)
├── Configuration::ConfigurationError (programming errors)
│   ├── SchemaRequiredError
│   ├── InvalidSchemaError
│   ├── InvalidConfigurationError
│   ├── NilUserError
│   └── Workflowable::Configuration::WorkflowConfigurationError
│       ├── StepNotFoundError
│       ├── InvalidStepError
│       └── DuplicateStepError
│
└── Runtime::RuntimeError (execution errors)
    ├── ValidationError
    ├── AuthorizationError
    ├── ResourceNotFoundError
    ├── DatabaseError
    ├── TransactionError
    ├── ExecutionError
    └── Workflowable::Runtime::WorkflowRuntimeError
        ├── WorkflowExecutionError
        ├── StepExecutionError
        └── RollbackError
```

## Error Categories

### Configuration Errors

Raised for **programming errors** - indicate bugs in service definition:

| Error | Code | When Raised |
|-------|------|-------------|
| `SchemaRequiredError` | `:schema_required` | Service missing `schema` block |
| `InvalidSchemaError` | `:configuration_error` | Invalid Dry::Schema syntax |
| `InvalidConfigurationError` | `:configuration_error` | Invalid settings |
| `NilUserError` | `:configuration_error` | User is nil when required |

```ruby
# Missing schema
class BadService < BetterService::Services::Base
  # No schema defined
end

BadService.new(user, params: {})
# => SchemaRequiredError: Schema is required
```

### Runtime Errors

Raised during **service execution** - indicate operational issues:

| Error | Code | When Raised |
|-------|------|-------------|
| `ValidationError` | `:validation_failed` | During `initialize` |
| `AuthorizationError` | `:unauthorized` | During `call` |
| `ResourceNotFoundError` | `:resource_not_found` | Record not found |
| `DatabaseError` | `:database_error` | Database operation failed |
| `TransactionError` | `:transaction_error` | Transaction failed |
| `ExecutionError` | `:execution_error` | Unexpected error |

### Workflow Errors

Raised during **workflow execution**:

| Error | Code | When Raised |
|-------|------|-------------|
| `WorkflowExecutionError` | `:workflow_failed` | Workflow failed |
| `StepExecutionError` | `:step_failed` | Step failed |
| `RollbackError` | `:rollback_failed` | Rollback failed |

## Error Flow

### Service Initialization

```
initialize()
    │
    ├─ Schema validation fails
    │      └─► ValidationError (immediate)
    │
    ├─ User is nil (not allowed)
    │      └─► NilUserError (immediate)
    │
    └─ Schema not defined
           └─► SchemaRequiredError (immediate)
```

### Service Execution

```
call()
    │
    ├─ Authorization fails
    │      └─► AuthorizationError
    │
    ├─ Search phase
    │      ├─ RecordNotFound
    │      │      └─► ResourceNotFoundError
    │      └─ Unexpected error
    │             └─► ExecutionError
    │
    ├─ Process phase
    │      ├─ Database validation fails
    │      │      └─► DatabaseError
    │      ├─ Transaction fails
    │      │      └─► TransactionError
    │      └─ Unexpected error
    │             └─► ExecutionError
    │
    └─ Respond phase
           └─ Unexpected error
                  └─► ExecutionError
```

## Accessing Error Information

### Error Code

```ruby
begin
  service.call
rescue BetterService::Errors::Runtime::ValidationError => e
  e.code  # => :validation_failed
end
```

### Error Context

Each error type provides relevant context:

```ruby
# ValidationError
e.context
# => {
#   service: "Products::CreateService",
#   validation_errors: {
#     name: ["is missing", "must be a string"],
#     price: ["must be greater than 0"]
#   }
# }

# AuthorizationError
e.context
# => {
#   service: "Products::UpdateService",
#   user_id: 123,
#   action: "update"
# }

# ResourceNotFoundError
e.context
# => {
#   service: "Products::ShowService",
#   model_class: "Product",
#   id: 999
# }
```

### Original Error

For wrapped exceptions:

```ruby
begin
  service.call
rescue BetterService::Errors::Runtime::DatabaseError => e
  e.original_error  # => ActiveRecord::RecordInvalid
  e.original_error.record.errors.full_messages
end
```

### Structured Hash

For logging/serialization:

```ruby
begin
  service.call
rescue BetterService::BetterServiceError => e
  Rails.logger.error(e.to_h.to_json)
end

# e.to_h produces:
# {
#   error_class: "BetterService::Errors::Runtime::ValidationError",
#   code: :validation_failed,
#   message: "Validation failed",
#   context: { ... },
#   timestamp: "2024-01-15T10:30:00Z",
#   backtrace: [...]
# }
```

## Success Responses

On success, services return hash structures:

```ruby
# Resource operations
{
  success: true,
  message: "Product created successfully",
  resource: #<Product id: 1, ...>,
  metadata: { action: :created }
}

# Collection operations
{
  success: true,
  message: "Products retrieved successfully",
  items: [...],
  metadata: { action: :listed, total: 42 }
}
```

## Next Steps

- [Error Codes Reference](./02-error-codes-reference.md) - Complete list of error codes
- [Error Handling Examples](./03-error-handling-examples.md) - Patterns for handling errors
