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

All services inherit from `BetterService::Services::Base` and follow a strict 5-phase execution flow:

1. **Validation** (Mandatory) - Schema validation via Dry::Schema
2. **Authorization** - Optional `authorize_with` block (fail-fast before search)
3. **Search** - Load raw data via `search_with` block
4. **Process** - Transform data via `process_with` block
5. **Respond** - Format response via `respond_with` block (optional viewer phase if enabled)

The phases execute sequentially in the `call` method, with automatic error handling and rollback on failure.

### Service Types

Single service class in `lib/better_service/services/`:

- **Base** - The foundation for all services. All services (CRUD and custom actions) inherit from a resource-specific BaseService (e.g., `Article::CreateService < Article::BaseService < BetterService::Services::Base`)

**Generated Service Patterns:**

All generated services (CRUD and action) inherit from a resource-specific BaseService and use:
- `performed_action :symbol` DSL for metadata (`:listed`, `:showed`, `:created`, `:updated`, `:destroyed`, or custom actions like `:publish`)
- `with_transaction true` for Create/Update/Destroy services (configurable for action services)

### Concerns Architecture

Seven concern modules in `lib/better_service/concerns/serviceable/` provide cross-cutting functionality:

- **Validatable** - Dry::Schema integration, defines `schema` DSL, raises `ValidationError` on failure during `initialize`
- **Authorizable** - `authorize_with` DSL and `allow_nil_user` DSL, raises `AuthorizationError` on failure during `call`
- **Transactional** - Database transaction wrapping via `prepend`, DSL: `with_transaction true/false`
- **Presentable** - Transforms data in phase 3 via `transform_with` block
- **Viewable** - Viewer configuration in phase 5
- **Cacheable** - Caching support for service results
- **Messageable** - Response message formatting helpers (`success_result`)

**Important:** `Transactional` is prepended (not included) to wrap the `process` method in `lib/better_service/services/base.rb`.

### Generators

Eleven Rails generators in `lib/generators/serviceable/` and `lib/generators/better_service/`:

**Service Generators (serviceable namespace):**
- `rails generate serviceable:scaffold Product` - Generates BaseService + all 5 CRUD services (supports `--presenter` option)
- `rails generate serviceable:base Product` - Generates BaseService, Repository, and I18n locale file
- `rails generate serviceable:index Product` - Index service (inherits from `BetterService::Services::Base` by default)
- `rails generate serviceable:show Product` - Show service
- `rails generate serviceable:create Product` - Create service with transaction
- `rails generate serviceable:update Product` - Update service with transaction
- `rails generate serviceable:destroy Product` - Destroy service with transaction
- `rails generate serviceable:action Product publish` - Custom action service
- `rails generate serviceable:workflow OrderPurchase` - Workflow orchestration

**CRUD Generator Options:**
- `--base_class=Article::BaseService` - Specify custom parent class (scaffold generator sets this automatically)

**Utility Generators (better_service namespace):**
- `rails generate better_service:install` - Generates initializer + copies locale file
- `rails generate better_service:presenter Product` - Creates presenter class and test
- `rails generate better_service:locale products` - Creates custom I18n locale file

Templates are in `lib/generators/serviceable/templates/` and `lib/generators/better_service/templates/`.

### Base Service Generator (serviceable:base)

The `serviceable:base` generator creates a centralized BaseService for a resource namespace, along with a Repository and I18n locale file.

**Usage:**
```bash
# Generate base infrastructure for Articles
rails generate serviceable:base Articles

# With namespace
rails generate serviceable:base Admin::Articles

# Skip specific components
rails generate serviceable:base Articles --skip_repository
rails generate serviceable:base Articles --skip_locale
rails generate serviceable:base Articles --skip_test
```

**Generated Files:**
```
app/services/articles/base_service.rb      # Articles::BaseService
app/repositories/articles_repository.rb    # ArticlesRepository
config/locales/articles_services.en.yml    # I18n messages
test/services/articles/base_service_test.rb
test/repositories/articles_repository_test.rb
```

**Integration with Scaffold:**
```bash
# Generate BaseService + all CRUD services inheriting from it
rails generate serviceable:scaffold Articles --base

# Combine with presenter
rails generate serviceable:scaffold Articles --base --presenter
```

When using `--base` with scaffold:
1. `Articles::BaseService` is generated first
2. All CRUD services inherit from `Articles::BaseService` instead of `BetterService::Services::XxxService`
3. Services use the repository declared in BaseService

**Generated Structure with --base:**
```ruby
# Articles::BaseService
class Articles::BaseService < BetterService::Services::Base
  include BetterService::Concerns::Serviceable::RepositoryAware

  messages_namespace :articles
  cache_contexts [:articles]
  repository :article
end

# Articles::IndexService (inherits from BaseService)
class Articles::IndexService < Articles::BaseService
  performed_action :listed

  schema do
    optional(:page).filled(:integer, gteq?: 1)
  end

  search_with do
    { items: article_repository.search({}, page: params[:page]).to_a }
  end
end
```

## Workflows

### Overview

Workflows orchestrate multiple services into a single cohesive business process. They provide:
- **Sequential execution** - Steps run in definition order
- **Conditional branching** - Multiple execution paths based on runtime conditions
- **Data passing** - Shared context between steps
- **Transaction support** - Database transaction wrapping
- **Automatic rollback** - Undo executed steps on failure
- **Lifecycle hooks** - Before/after callbacks

All workflows inherit from `BetterService::Workflows::Base` (located in `lib/better_service/workflows/base.rb`).

### Basic Linear Workflow

```ruby
class Order::PurchaseWorkflow < BetterService::Workflows::Base
  with_transaction true

  step :validate_cart,
       with: Order::ValidateCartService,
       input: ->(ctx) { { cart_id: ctx.cart_id } }

  step :charge_payment,
       with: Payment::ChargeService,
       input: ->(ctx) { { amount: ctx.validate_cart.total } },
       rollback: ->(ctx) { Payment::RefundService.new(ctx.user, params: { charge_id: ctx.charge_payment.id }).call }

  step :create_order,
       with: Order::CreateService,
       input: ->(ctx) { { cart: ctx.validate_cart, charge: ctx.charge_payment } }

  step :send_email,
       with: Email::ConfirmationService,
       input: ->(ctx) { { order: ctx.create_order } },
       optional: true

  step :clear_cart,
       with: Cart::ClearService,
       input: ->(ctx) { { cart_id: ctx.cart_id } }
end

# Usage:
result = Order::PurchaseWorkflow.new(current_user, params: { cart_id: 123 }).call
```

### Conditional Branching (NEW)

Workflows support **non-linear, conditional execution** with multi-way branching. Only one branch executes based on the first matching condition.

#### Syntax

```ruby
branch do
  on ->(ctx) { condition1 } do
    # Steps for path 1
  end

  on ->(ctx) { condition2 } do
    # Steps for path 2
  end

  otherwise do
    # Default path if no condition matches
  end
end
```

#### Branch Execution Rules

1. **First-match wins** - Conditions evaluated in order, first true condition executes
2. **Single path** - Only one branch executes per `branch` block
3. **Otherwise is optional** - But without it, an error is raised if no condition matches
4. **Nested branches** - Branches can contain other `branch` blocks
5. **Context access** - Conditions have full access to context and user
6. **Rollback awareness** - Only executed branch steps are rolled back on failure

#### Example: Payment Method Routing

```ruby
class Order::ProcessPaymentWorkflow < BetterService::Workflows::Base
  with_transaction true

  step :validate_order,
       with: Order::ValidateService,
       input: ->(ctx) { { order_id: ctx.order_id } }

  # Branch based on payment method
  branch do
    on ->(ctx) { ctx.validate_order.payment_method == 'credit_card' } do
      step :charge_credit_card,
           with: Payment::ChargeCreditCardService,
           input: ->(ctx) { { order: ctx.validate_order } }

      step :verify_3d_secure,
           with: Payment::Verify3DSecureService,
           input: ->(ctx) { { charge: ctx.charge_credit_card } },
           optional: true
    end

    on ->(ctx) { ctx.validate_order.payment_method == 'paypal' } do
      step :create_paypal_order,
           with: Payment::Paypal::CreateOrderService,
           input: ->(ctx) { { order: ctx.validate_order } }

      step :capture_paypal_payment,
           with: Payment::Paypal::CaptureService,
           input: ->(ctx) { { paypal_order: ctx.create_paypal_order } }
    end

    on ->(ctx) { ctx.validate_order.payment_method == 'bank_transfer' } do
      step :generate_transfer_reference,
           with: Payment::BankTransfer::GenerateReferenceService,
           input: ->(ctx) { { order: ctx.validate_order } }

      step :send_transfer_instructions,
           with: Email::BankInstructionsService,
           input: ->(ctx) { { order: ctx.validate_order, reference: ctx.generate_transfer_reference } }
    end

    otherwise do
      step :log_unsupported_method,
           with: Logging::UnsupportedPaymentService,
           input: ->(ctx) { { order: ctx.validate_order } }
    end
  end

  # Steps after branch execute regardless of which path was taken
  step :update_order_status,
       with: Order::UpdateStatusService,
       input: ->(ctx) { { order_id: ctx.validate_order.id, status: 'processing' } }

  step :send_confirmation,
       with: Email::OrderConfirmationService,
       input: ->(ctx) { { order: ctx.validate_order } }
end
```

#### Nested Branches

Branches can be nested for complex conditional logic:

```ruby
class Document::ApprovalWorkflow < BetterService::Workflows::Base
  step :validate_document,
       with: Document::ValidateService

  branch do
    on ->(ctx) { ctx.validate_document.type == 'contract' } do
      step :legal_review,
           with: Legal::ReviewService

      # Nested branch based on contract value
      branch do
        on ->(ctx) { ctx.validate_document.value > 100_000 } do
          step :ceo_approval,
               with: Approval::CEOService

          step :board_approval,
               with: Approval::BoardService
        end

        on ->(ctx) { ctx.validate_document.value > 10_000 } do
          step :manager_approval,
               with: Approval::ManagerService
        end

        otherwise do
          step :supervisor_approval,
               with: Approval::SupervisorService
        end
      end
    end

    on ->(ctx) { ctx.validate_document.type == 'invoice' } do
      branch do
        on ->(ctx) { ctx.validate_document.amount > 5_000 } do
          step :finance_approval,
               with: Approval::FinanceService
        end

        otherwise do
          step :auto_approve,
               with: Approval::AutoApproveService
        end
      end
    end

    otherwise do
      step :standard_approval,
           with: Approval::StandardService
    end
  end

  step :finalize_document,
       with: Document::FinalizeService
end
```

#### Branch Metadata

Workflow results include `branches_taken` metadata showing which branches were executed:

```ruby
result = Order::ProcessPaymentWorkflow.new(user, params: { order_id: 123 }).call

result[:metadata]
# => {
#   workflow: "Order::ProcessPaymentWorkflow",
#   steps_executed: [:validate_order, :charge_credit_card, :verify_3d_secure, :update_order_status, :send_confirmation],
#   branches_taken: ["branch_1:on_1"],  # First branch, first condition
#   duration_ms: 1234.56
# }
```

For nested branches:

```ruby
result[:metadata][:branches_taken]
# => ["branch_1:on_1", "nested_branch_1:on_2"]
# First branch took first condition, nested branch took second condition
```

#### Complex Conditions

Branch conditions can include complex boolean logic:

```ruby
branch do
  # Enterprise customers with custom billing
  on ->(ctx) {
    ctx.user.account_type == 'enterprise' &&
    ctx.subscription.custom_billing? &&
    ctx.subscription.annual_value > 50_000
  } do
    step :custom_enterprise_flow, with: Enterprise::CustomFlowService
  end

  # Premium with valid payment method
  on ->(ctx) {
    ctx.user.premium? &&
    ctx.payment_method.present? &&
    ctx.payment_method.valid? &&
    ctx.payment_method.expires_at > 30.days.from_now
  } do
    step :premium_flow, with: Premium::FlowService
  end

  # Free tier
  on ->(ctx) { ctx.user.free_tier? } do
    step :free_flow, with: Free::FlowService
  end

  otherwise do
    step :default_flow, with: Default::FlowService
  end
end
```

### Workflow Context

The `Workflowable::Context` object (in `lib/better_service/concerns/workflowable/context.rb`) is shared across all workflow steps:

**Storing step results:**
- Services return `{ resource: {...} }` → stored as `context.step_name`
- Services return `{ items: [...] }` → stored as `context.step_name`
- Otherwise, full result hash stored

**Accessing data:**
```ruby
input: ->(ctx) {
  {
    order_id: ctx.create_order.id,           # From step :create_order
    payment_id: ctx.charge_payment.id,        # From step :charge_payment
    user_email: ctx.user.email                # From workflow user
  }
}
```

**Dynamic attributes:**
```ruby
context.order = order_object        # Setter
context.order                       # Getter
context.add(:key, value)           # Explicit add
context.get(:key)                  # Explicit get
```

### Workflow Rollback

When a step fails in a branch:
1. **Only executed steps are rolled back** (not skipped or non-executed branch steps)
2. **Rollback executes in reverse order** (LIFO)
3. **Each step's `rollback` block is called** if defined

```ruby
step :charge_payment,
     with: Payment::ChargeService,
     rollback: ->(ctx) {
       # Undo the charge
       Payment::RefundService.new(ctx.user, params: { charge_id: ctx.charge_payment.id }).call
     }
```

**Branch-specific rollback:**
Only the steps in the executed branch are rolled back, not steps from other branches.

### Error Handling in Workflows

**Configuration Errors:**
- `Errors::Configuration::InvalidConfigurationError` - No matching branch and no otherwise

**Runtime Errors:**
- `Errors::Workflowable::Runtime::StepExecutionError` - Step failed
- `Errors::Workflowable::Runtime::WorkflowExecutionError` - Workflow failed
- `Errors::Workflowable::Runtime::RollbackError` - Rollback failed

```ruby
begin
  result = MyWorkflow.new(user, params: params).call
rescue BetterService::Errors::Configuration::InvalidConfigurationError => e
  # No branch matched and no otherwise defined
  Rails.logger.error "Workflow misconfigured: #{e.message}"
rescue BetterService::Errors::Workflowable::Runtime::StepExecutionError => e
  # Step failed, rollback executed
  Rails.logger.error "Step #{e.context[:step]} failed: #{e.message}"
end
```

### Generator

Generate workflows with:

```bash
rails generate workflowable:workflow Order::Purchase
```

This creates:
- `app/workflows/order/purchase_workflow.rb` - Workflow class
- `test/workflows/order/purchase_workflow_test.rb` - Test file

The generated template includes commented examples of branching.

## Key Design Patterns

### Mandatory Schema Validation
All services MUST define a `schema` block. The base class validates schema presence in `lib/better_service/services/base.rb` during `initialize`, raising `SchemaRequiredError` if missing. Parameter validation via Dry::Schema happens during `initialize` and raises `ValidationError` if params are invalid, before `call` is ever executed.

### DSL Implementation
Phase blocks (`search_with`, `process_with`, etc.) are stored as class attributes and executed via `instance_exec` in the corresponding phase methods. This allows access to `user`, `params`, and helper methods within blocks.

### Transaction Handling
Create/Update/Destroy services enable transactions by default. The `Transactional` concern is prepended (not included) to wrap the `process` method with `ActiveRecord::Base.transaction` when enabled via the `with_transaction` DSL.

### Metadata System
All services automatically include `metadata: { action: :action_name }` in success responses. The action name is set via `performed_action :symbol` DSL in each service class. Additional metadata can be merged by returning `{ metadata: {...} }` from `process_with` blocks.

### Message System (I18n)
Services support internationalization via the `message(key_path, interpolations = {})` helper in the Messageable concern. Messages follow a 3-level fallback chain:
1. **Custom namespace** - `{namespace}.services.{action}.{key}` (if `messages_namespace :namespace` is set)
2. **Default BetterService messages** - `better_service.services.default.{action}`
3. **Key itself** - Returns the key if no translations found

Default messages are in `config/locales/better_service.en.yml`. Custom locale files can be generated with `rails generate better_service:locale namespace`.

**Templates usage**: All 5 CRUD service templates use `message("action.success")` in `respond_with` blocks instead of hardcoded strings.

### Auto-Invalidation Cache
Create/Update/Destroy services have `_auto_invalidate_cache = true` by default (set in each service class). When `cache_contexts` are defined, cache is automatically invalidated after successful write operations in `Base#call` (after process phase). The helper method `should_auto_invalidate_cache?` checks:
- Auto-invalidation is enabled
- Cache contexts are defined
- Service is Create/Update/Destroy type

Disable with `auto_invalidate_cache false` DSL for manual control.

### Presenter System
Optional presenter layer via `BetterService::Presenter` base class in `lib/better_service/presenter.rb`. Presenters transform data in services via the `transform_with` block (Presentable concern).

**Available methods in Presenter:**
- `object` - The resource being presented
- `options` - Options hash from `presenter_options` block
- `current_user` - Shortcut for `options[:current_user]`
- `as_json(opts)` - Format object as JSON
- `to_json(opts)` - Serialize to JSON string
- `to_h` - Alias for `as_json`

**Generators:**
- `rails generate better_service:presenter Product` - Creates presenter class and test
- `rails generate serviceable:scaffold Product --presenter` - Creates services + presenter

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

Tests are in `test/` directory. The test suite excludes dummy app files via `Rakefile:8-9`. Generator tests are now enabled and run as part of the test suite.

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

### Testing Workflows with Branching

Workflow branching tests verify that conditional execution paths work correctly. The test suite includes multiple test files covering different aspects:

**Test Files:**
- `test/workflow_branch_test.rb` - Basic branching functionality (12 tests)
- `test/integration/workflow_branching_integration_test.rb` - Real database integration (10+ tests)
- `test/workflow/branching_edge_cases_test.rb` - Edge cases and boundary conditions (15 tests)
- `test/workflow/branching_performance_test.rb` - Performance benchmarks (5 tests)
- `test/examples/workflow_branching_examples_test.rb` - Real-world examples (4+ tests)

#### Testing Branch Conditions

```ruby
test "branch takes correct path based on condition" do
  user = User.new(1, premium: true)
  workflow = MyWorkflow.new(user, params: { product_id: 123 })

  result = workflow.call

  assert result[:success]
  # Verify correct steps were executed
  assert_equal [:validate, :premium_feature, :finalize], result[:metadata][:steps_executed]
  # Verify correct branch was taken
  assert_includes result[:metadata][:branches_taken], "branch_1:on_1"
  # Verify context has correct data
  assert_equal "premium", result[:context].premium_feature[:tier]
end
```

#### Testing Branch Metadata

Branch execution is tracked in `result[:metadata][:branches_taken]`:

```ruby
# Single branch decision
result[:metadata][:branches_taken]
# => ["branch_1:on_2"]  # First branch, second condition

# Nested branches
result[:metadata][:branches_taken]
# => ["branch_1:on_1", "nested_branch_1:otherwise"]  # Outer + inner decisions
```

#### Testing Multiple Branch Paths

Test each possible path through a branch:

```ruby
class TestWorkflow < BetterService::Workflows::Base
  step :validate, with: ValidateService

  branch do
    on ->(ctx) { ctx.validate.type == "A" } do
      step :handle_a, with: HandleAService
    end

    on ->(ctx) { ctx.validate.type == "B" } do
      step :handle_b, with: HandleBService
    end

    otherwise do
      step :handle_default, with: HandleDefaultService
    end
  end
end

# Test path A
test "handles type A" do
  result = TestWorkflow.new(user, params: { type: "A" }).call
  assert_equal [:validate, :handle_a], result[:metadata][:steps_executed]
end

# Test path B
test "handles type B" do
  result = TestWorkflow.new(user, params: { type: "B" }).call
  assert_equal [:validate, :handle_b], result[:metadata][:steps_executed]
end

# Test otherwise path
test "handles unknown type" do
  result = TestWorkflow.new(user, params: { type: "X" }).call
  assert_equal [:validate, :handle_default], result[:metadata][:steps_executed]
end
```

#### Testing Nested Branches

Verify deeply nested branch decisions are tracked correctly:

```ruby
test "nested branches track all decisions" do
  workflow = NestedWorkflow.new(user, params: { ... })
  result = workflow.call

  assert result[:success]
  # Verify both outer and inner branch decisions
  assert_equal 2, result[:metadata][:branches_taken].count
  assert_includes result[:metadata][:branches_taken], "branch_1:on_1"
  assert_includes result[:metadata][:branches_taken], "nested_branch_1:on_2"
end
```

#### Testing Branch Failure and Rollback

Verify that failures in branches trigger rollback correctly:

```ruby
test "branch failure triggers rollback" do
  workflow = FailingBranchWorkflow.new(user, params: { ... })

  error = assert_raises(BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError) do
    workflow.call
  end

  assert_match /Service failed/, error.message
  # Verify only executed steps were rolled back (not other branch paths)
end
```

#### Testing Configuration Errors

Verify invalid branch configurations are caught:

```ruby
test "no matching branch without otherwise raises error" do
  workflow = NoBranchMatchWorkflow.new(user, params: { ... })

  error = assert_raises(BetterService::Errors::Configuration::InvalidConfigurationError) do
    workflow.call
  end

  assert_match /No matching branch found/, error.message
  assert_equal :configuration_error, error.code
end
```

#### Mock Services for Branch Tests

Create lightweight mock services for testing branch logic:

```ruby
class MockService < BetterService::Services::Base
  schema { optional(:context).filled }

  process_with do
    { resource: { executed: true, data: params[:data] || "default" } }
  end
end

# Use in workflow tests
class TestWorkflow < BetterService::Workflows::Base
  branch do
    on ->(ctx) { ctx.condition } do
      step :mock_step, with: MockService
    end
  end
end
```

#### Integration Tests with Real Models

Test branching with database operations:

```ruby
test "branch workflow with real database models" do
  product = Product.create!(name: "Premium Widget", price: 199.99, user: @user)

  workflow = ProductWorkflow.new(@user, params: { product_id: product.id })
  result = workflow.call

  assert result[:success]
  # Verify database changes
  assert Product.exists?(id: product.id)
  product.reload
  assert product.published
end
```

#### Manual Testing

Run interactive tests with real database models:

```bash
cd test/dummy
rails console
load '../../manual_test.rb'
```

This runs comprehensive branching tests with:
- Real database models (User, Product, Booking)
- Automatic transaction rollback
- Colored output showing success/failure
- Timing statistics

The manual tests cover:
1. E-commerce order processing with payment method branching
2. Content approval workflow with nested branches
3. Subscription renewal with complex conditional logic

All tests run in database transactions and automatically rollback, leaving no data behind.

## Code Style

This project uses `rubocop-rails-omakase` gem for linting. Follow Rails Omakase conventions. The configuration is in `.rubocop.yml`.
