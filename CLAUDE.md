# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BetterService is a Ruby gem that provides a DSL-based Service Objects framework for Rails applications. It implements a clean 5-phase architecture for business logic with built-in validation, authorization, transactions, and metadata tracking.

**Key Technologies:**
- Ruby >= 3.0.0
- Rails >= 8.1.1
- Dry::Schema ~> 1.13 for validation
- Minitest for testing
- RuboCop (Rails Omakase) for linting

## Commands

### Development
```bash
# Install dependencies
bundle install

# Run all tests
bundle exec rake
# or
bundle exec rake test
# or
bin/test

# Run linting
bin/rubocop

# Fix linting issues automatically
bin/rubocop -a
```

### Manual Testing
```bash
cd test/dummy
rails console
load '../../manual_test.rb'
```

This runs 8 comprehensive integration tests with automatic database rollback.

## Architecture

### 5-Phase Service Flow

All services inherit from `BetterService::Base` and follow a strict 5-phase execution flow in `lib/better_service/base.rb:64-85`:

1. **Validation** (Mandatory) - Schema validation via Dry::Schema
2. **Authorization** - Optional `authorize_with` block (fail-fast before search)
3. **Search** - Load raw data via `search_with` block
4. **Process** - Transform data via `process_with` block
5. **Respond** - Format response via `respond_with` block (optional viewer phase if enabled)

The phases execute sequentially in the `call` method, with automatic error handling and rollback on failure.

### Service Types

Six specialized service classes in `lib/better_service/`:

- **IndexService** - List/collection operations, returns `{ items: [], metadata: {...} }`
- **ShowService** - Single resource retrieval, returns `{ resource: {}, metadata: {...} }`
- **CreateService** - Resource creation with transactions enabled by default, action: `:created`
- **UpdateService** - Resource updates with transactions enabled by default, action: `:updated`
- **DestroyService** - Resource deletion with transactions enabled by default, action: `:destroyed`
- **ActionService** - Custom actions with configurable `action_name`, transactions optional

### Concerns Architecture

Seven concern modules in `lib/better_service/concerns/` provide cross-cutting functionality:

- **Validatable** - Dry::Schema integration, defines `schema` DSL, raises `ValidationError` on failure during `initialize`
- **Authorizable** - `authorize_with` DSL, raises `AuthorizationError` on failure during `call`
- **Transactional** - Database transaction wrapping via `prepend`, DSL: `with_transaction true/false`
- **Presentable** - Transforms data in phase 3 via `transform_with` block
- **Viewable** - Viewer configuration in phase 5
- **Cacheable** - Caching support for service results
- **Messageable** - Response message formatting helpers

**Important:** `Transactional` is prepended (not included) to wrap the `process` method in `lib/better_service/base.rb:28`.

### Generators

Seven Rails generators in `lib/generators/better_service/`:

- `rails generate better_service:scaffold Product` - Generates all 5 CRUD services
- `rails generate better_service:index Product`
- `rails generate better_service:show Product`
- `rails generate better_service:create Product`
- `rails generate better_service:update Product`
- `rails generate better_service:destroy Product`
- `rails generate better_service:action Product publish` - Custom action service

Templates are in `lib/generators/better_service/templates/`.

## Key Design Patterns

### Mandatory Schema Validation
All services MUST define a `schema` block. The base class validates schema presence in `lib/better_service/base.rb` during `initialize`, raising `SchemaRequiredError` if missing. Parameter validation via Dry::Schema happens during `initialize` and raises `ValidationError` if params are invalid, before `call` is ever executed.

### DSL Implementation
Phase blocks (`search_with`, `process_with`, etc.) are stored as class attributes and executed via `instance_exec` in the corresponding phase methods. This allows access to `user`, `params`, and helper methods within blocks.

### Transaction Handling
Create/Update/Destroy services enable transactions by default. The `Transactional` concern (prepended in `base.rb:28`) wraps the `process` method with `ActiveRecord::Base.transaction` when enabled.

### Metadata System
All services automatically include `metadata: { action: :action_name }` in success responses. The action name is set via `self._action_name = :symbol` in each service class. Additional metadata can be merged by returning `{ metadata: {...} }` from `process_with` blocks.

### Error Handling

**BetterService uses a Pure Exception Pattern** where all errors raise exceptions with rich context information. This ensures consistent behavior across all environments.

#### Exception Hierarchy

All exceptions inherit from `BetterService::BetterServiceError` with three main categories:

**Configuration Errors** (programming errors):
- `Errors::Configuration::SchemaRequiredError` - Missing schema definition
- `Errors::Configuration::NilUserError` - User is nil when required
- `Errors::Configuration::InvalidSchemaError` - Invalid schema syntax
- `Errors::Configuration::InvalidConfigurationError` - Invalid config settings

**Runtime Errors** (execution errors):
- `Errors::Runtime::ValidationError` - Parameter validation failed (raised during `initialize`)
- `Errors::Runtime::AuthorizationError` - User not authorized (raised during `call`)
- `Errors::Runtime::ResourceNotFoundError` - Record not found
- `Errors::Runtime::DatabaseError` - Database operation failed
- `Errors::Runtime::TransactionError` - Transaction rollback
- `Errors::Runtime::ExecutionError` - Unexpected error

**Workflowable Errors** (workflow execution):
- `Errors::Workflowable::Runtime::WorkflowExecutionError` - Workflow failed
- `Errors::Workflowable::Runtime::StepExecutionError` - Step failed
- `Errors::Workflowable::Runtime::RollbackError` - Rollback failed

#### Exception Information

All `BetterServiceError` exceptions provide:
- `#message` - Human-readable error message
- `#code` - Symbol code for programmatic handling (e.g., `:validation_failed`, `:unauthorized`)
- `#context` - Hash with service-specific context (service name, params, validation errors, etc.)
- `#original_error` - The original exception if wrapping another error
- `#timestamp` - When the error occurred
- `#to_h` - Structured hash representation with all information
- `#detailed_message` - Extended message with context
- `#backtrace` - Enhanced backtrace including original error backtrace

#### Error Flow

1. **Validation Errors**: Raised during service `initialize` (not in `call`)
   ```ruby
   # This raises ValidationError immediately
   service = MyService.new(user, params: invalid_params)
   ```

2. **Authorization Errors**: Raised during `call` before search phase
   ```ruby
   begin
     service.call
   rescue BetterService::Errors::Runtime::AuthorizationError => e
     # Handle authorization failure
   end
   ```

3. **Runtime Errors**: Raised during `call` execution
   ```ruby
   begin
     service.call
   rescue BetterService::Errors::Runtime::DatabaseError => e
     # Database constraint or validation failed
   rescue BetterService::Errors::Runtime::ResourceNotFoundError => e
     # Record not found
   rescue BetterService::Errors::Runtime::ExecutionError => e
     # Unexpected error with original error in e.original_error
   end
   ```

#### Success Responses

On success, services return hash structures:
- `{ success: true, message: "...", metadata: {...}, **data }`
- For resources: `{ success: true, resource: {...}, metadata: { action: :created } }`
- For collections: `{ success: true, items: [...], metadata: { action: :listed } }`

## Testing

Tests are in `test/` directory. The test suite excludes dummy app files and generator tests via `Rakefile:8-10`.

Test structure:
- Unit tests for each service type and concern
- Integration tests in `manual_test.rb` for end-to-end workflows
- Dummy Rails app in `test/dummy/` for integration testing

### Testing Error Handling

All error scenarios use `assert_raises` since BetterService uses Pure Exception Pattern:

```ruby
# Validation errors (raised during initialize)
test "validates required params" do
  error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
    MyService.new(user, params: invalid_params)
  end

  assert_equal :validation_failed, error.code
  assert error.context[:validation_errors].key?(:name)
end

# Authorization errors (raised during call)
test "checks authorization" do
  error = assert_raises(BetterService::Errors::Runtime::AuthorizationError) do
    MyService.new(user, params: params).call
  end

  assert_equal :unauthorized, error.code
  assert_equal "MyService", error.context[:service]
end

# Database errors
test "handles database errors" do
  error = assert_raises(BetterService::Errors::Runtime::DatabaseError) do
    service.call
  end

  assert_equal :database_error, error.code
  assert_instance_of ActiveRecord::RecordInvalid, error.original_error
end
```

When writing tests, follow the existing pattern of testing both success and exception paths, including validation errors, authorization failures, database errors, and transaction rollbacks.

## Code Style

This project uses `rubocop-rails-omakase` gem for linting. Follow Rails Omakase conventions. The configuration is in `.rubocop.yml`.
