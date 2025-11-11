# BetterService Overview

## What is BetterService?

BetterService is a service object framework for Ruby/Rails applications that provides a structured, testable, and maintainable approach to handling business logic.

## Key Features

- **6 Service Types**: IndexService, ShowService, CreateService, UpdateService, DestroyService, ActionService
- **5-Phase Execution Flow**: Validation → Authorization → Search → Process → Respond
- **Automatic Transactions**: Built-in rollback on errors
- **Schema Validation**: Dry::Schema integration for parameter validation
- **Authorization**: Built-in authorization blocks
- **Cache Management**: Automatic cache invalidation
- **Workflows**: Compose multiple services with automatic rollback
- **Generators**: Rails generators for rapid service creation

## Documentation Structure

This context7 documentation is organized into 5 main categories:

### 1. Services (`/services`)
Examples for all 6 service types plus core features:
- IndexService, ShowService, CreateService, UpdateService, DestroyService, ActionService
- Schema validation patterns
- Authorization patterns
- Transaction management
- Cache management
- Presenters

### 2. Workflows (`/workflows`)
Multi-step operation patterns:
- Workflow basics and composition
- Step configuration (conditional, parameter mapping, error handling)
- Real-world workflow patterns

### 3. Generators (`/generators`)
Rails generator usage:
- Service generators (index, show, create, update, destroy, action)
- Workflow generators
- Generator options (--cache, --authorize, --presenter)

### 4. Examples (`/examples`)
Common patterns and guidelines:
- Proven patterns for common scenarios
- Anti-patterns to avoid
- Best practices and conventions

### 5. Advanced Features (`/advanced`)
Production-ready instrumentation and monitoring:
- ActiveSupport::Notifications integration
- Service lifecycle events (started, completed, failed)
- Cache events (hit, miss)
- Built-in StatsSubscriber for metrics collection
- Built-in LogSubscriber for automatic logging
- Custom subscriber examples for monitoring systems
- Configuration for different environments

## Critical Rules

### ALWAYS Use DSL Methods

✅ **CORRECT:**
```ruby
class MyService < BetterService::CreateService
  process_with do |data|
    # Your logic here
  end
end
```

❌ **WRONG:**
```ruby
class MyService < BetterService::CreateService
  def process(data)  # ❌ NEVER override methods directly
    # Your logic here
  end
end
```

### NEVER Call Services from Services

✅ **CORRECT - Use Workflows:**
```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  step :create_order, with: Order::CreateService
  step :charge_payment, with: Payment::ChargeService
end
```

❌ **WRONG - Calling Service from Service:**
```ruby
class Order::CreateService < BetterService::CreateService
  process_with do |data|
    order = Order.create!(params)
    Payment::ChargeService.new(user, params: {}).call  # ❌ NEVER do this
  end
end
```

## Usage Example

```ruby
# In controller
class ProductsController < ApplicationController
  def index
    result = Product::IndexService.new(current_user, params: index_params).call
    @products = result[:items]
  end

  def create
    result = Product::CreateService.new(current_user, params: create_params).call
    @product = result[:resource]
    redirect_to @product
  rescue BetterService::Errors::Runtime::SchemaValidationError => e
    flash[:error] = e.message
    render :new
  end
end
```

## Learn More

- Full documentation: `/docs`
- Service examples: `/context7/services`
- Workflow examples: `/context7/workflows`
- Generator examples: `/context7/generators`
- Common patterns: `/context7/examples`
- Advanced features: `/context7/advanced`
