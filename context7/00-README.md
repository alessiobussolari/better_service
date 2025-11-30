# BetterService

Service Objects framework for Ruby/Rails with 5-phase architecture, Result wrapper, and Repository pattern.

**Version 2.0.0** - 435 tests passing

---

## Quick Start

### Generate and Use a Service

Generate a complete service stack and use it in a controller.

```ruby
# 1. Generate BaseService + Repository + locale
rails g serviceable:base Product

# 2. Generate CRUD services
rails g serviceable:scaffold Product --base

# 3. Use in controller
class ProductsController < ApplicationController
  def create
    result = Product::CreateService.new(current_user, params: product_params).call

    if result.success?
      render json: { product: result.resource, message: result.message }, status: :created
    else
      render json: { error: result.message, code: result.meta[:error_code] }, status: :unprocessable_entity
    end
  rescue BetterService::Errors::Runtime::ValidationError => e
    render json: { errors: e.context[:validation_errors] }, status: :unprocessable_entity
  end
end
```

--------------------------------

## 5-Phase Execution Flow

### Execution Phases

Every service executes through 5 phases in strict order.

```ruby
# Phase 1: Validation (during initialize)
# - Dry::Schema parameter validation
# - Raises ValidationError if invalid

# Phase 2: Authorization (during call)
# - User permission check via authorize_with
# - Raises AuthorizationError if denied

# Phase 3: Search
# - Load required data via search_with
# - Returns { resource: obj } or { items: [...] }

# Phase 4: Process
# - Execute business logic via process_with
# - Must return { resource: obj } for proper extraction

# Phase 5: Respond
# - Format response via respond_with
# - Returns BetterService::Result
```

--------------------------------

## Result Wrapper

### Using the Result Object

All services return `BetterService::Result` with success/failure handling.

```ruby
result = Product::CreateService.new(user, params: { name: "Widget", price: 99.99 }).call

result.success?   # => true
result.resource   # => #<Product id: 1, name: "Widget">
result.meta       # => { action: :created, success: true }
result.message    # => "Product created successfully"

# Destructuring supported
product, meta = result
```

--------------------------------

## Critical Rules

### Use next NOT return in authorize_with

Blocks don't support `return` - use `next` instead.

```ruby
# CORRECT
authorize_with do
  next true if user.admin?
  user.seller?
end

# WRONG - LocalJumpError!
authorize_with do
  return true if user.admin?
end
```

--------------------------------

### Return { resource: obj } in process_with

Resource extraction requires proper hash wrapper.

```ruby
# CORRECT
process_with do |data|
  product = product_repository.create!(params)
  { resource: product }
end

# WRONG - Resource won't be extracted
process_with do |data|
  product_repository.create!(params)
end
```

--------------------------------

### Never Call Services from Services

Use Workflows for service composition to ensure proper rollback.

```ruby
# WRONG - No rollback on failure
process_with do |data|
  order = Order.create!(params)
  Payment::ChargeService.new(user, params: {}).call
end

# CORRECT - Use Workflow
class Order::CheckoutWorkflow < BetterService::Workflows::Base
  step :create_order, with: Order::CreateService
  step :charge_payment, with: Payment::ChargeService
end
```

--------------------------------

## Documentation Index

- [01-services.md](01-services.md) - Service patterns and DSL
- [02-result.md](02-result.md) - Result wrapper API
- [03-repository.md](03-repository.md) - Repository pattern
- [04-workflows.md](04-workflows.md) - Workflow orchestration
- [05-errors.md](05-errors.md) - Error handling
- [06-generators.md](06-generators.md) - Rails generators
- [07-configuration.md](07-configuration.md) - Configuration options
- [08-i18n.md](08-i18n.md) - Internationalization
- [09-anti-patterns.md](09-anti-patterns.md) - Common mistakes
- [10-api-reference.md](10-api-reference.md) - API reference
- [11-architecture-diagrams.md](11-architecture-diagrams.md) - Visual architecture diagrams
