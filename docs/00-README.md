# BetterService Documentation

User-facing documentation for BetterService - a Service Objects framework for Rails.

---

## What is BetterService?

BetterService provides a clean, DSL-based approach to organizing business logic in Rails applications. It implements a 5-phase architecture that separates validation, authorization, data loading, processing, and response formatting.

---

## Key Features

- **5-Phase Execution** - Structured flow: Validation → Authorization → Search → Process → Respond
- **Result Wrapper** - Consistent success/failure handling with `BetterService::Result`
- **Repository Pattern** - Clean data access abstraction
- **Workflow Orchestration** - Compose services with automatic rollback
- **Rails Generators** - Rapid scaffolding of services and workflows
- **I18n Support** - Built-in internationalization for messages

---

## Documentation Index

### Getting Started
- [01-getting-started.md](01-getting-started.md) - Installation and first service

### Core Concepts
- [02-services.md](02-services.md) - Service patterns and DSL
- [03-validation.md](03-validation.md) - Schema validation
- [04-authorization.md](04-authorization.md) - Authorization patterns

### Response Handling
- [05-result.md](05-result.md) - Result wrapper guide

### Data Access
- [06-repository.md](06-repository.md) - Repository pattern

### Orchestration
- [07-workflows.md](07-workflows.md) - Workflow guide

### Error Handling
- [08-errors.md](08-errors.md) - Error handling

### Tools
- [09-generators.md](09-generators.md) - Generator reference
- [10-configuration.md](10-configuration.md) - Configuration guide

### Testing
- [11-testing.md](11-testing.md) - Testing patterns

### Architecture
- [12-architecture-diagrams.md](12-architecture-diagrams.md) - Visual architecture diagrams

---

## Quick Example

```ruby
# Generate services
rails g serviceable:scaffold Product --base

# Use in controller
class ProductsController < ApplicationController
  def create
    result = Product::CreateService.new(current_user, params: product_params).call

    if result.success?
      render json: { product: result.resource }, status: :created
    else
      render json: { error: result.message }, status: :unprocessable_entity
    end
  end
end
```

---

## Requirements

- Ruby >= 3.0.0
- Rails >= 8.1.1
- Dry::Schema ~> 1.13
