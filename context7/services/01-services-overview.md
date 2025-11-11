# Services Overview & Getting Started

## What are Services?

Services in BetterService are specialized classes that encapsulate business logic. Each service type is optimized for a specific CRUD operation.

## 6 Service Types

### 1. IndexService
List/filter resources with pagination.

```ruby
class Product::IndexService < BetterService::IndexService
  model_class Product

  search_with do
    { items: model_class.all }
  end
end
```

### 2. ShowService
Display a single resource.

```ruby
class Product::ShowService < BetterService::ShowService
  model_class Product

  search_with do
    { resource: model_class.find(params[:id]) }
  end
end
```

### 3. CreateService
Create new resources.

```ruby
class Product::CreateService < BetterService::CreateService
  model_class Product

  process_with do |data|
    { resource: model_class.create!(params) }
  end
end
```

### 4. UpdateService
Modify existing resources.

```ruby
class Product::UpdateService < BetterService::UpdateService
  model_class Product

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    data[:resource].update!(params.except(:id))
    { resource: data[:resource] }
  end
end
```

### 5. DestroyService
Delete resources.

```ruby
class Product::DestroyService < BetterService::DestroyService
  model_class Product

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    data[:resource].destroy!
    { resource: data[:resource] }
  end
end
```

### 6. ActionService
Custom business actions.

```ruby
class Order::ApproveService < BetterService::ActionService
  model_class Order
  action_name :approve

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    data[:resource].update!(status: 'approved')
    { resource: data[:resource] }
  end
end
```

## 5-Phase Execution Flow

Every service executes through 5 phases:

1. **Validation** - Validate params with Dry::Schema
2. **Authorization** - Check if user can execute
3. **Search** - Fetch required data
4. **Process** - Execute business logic
5. **Respond** - Format and return result

## Getting Started

### Install the Gem

```ruby
# Gemfile
gem 'better_service'

# Then run
bundle install
```

### Generate Your First Service

```bash
rails g serviceable:index Product
```

Creates:
```ruby
# app/services/product/index_service.rb
module Product
  class IndexService < BetterService::IndexService
    model_class Product

    schema do
      optional(:page).filled(:integer, gteq?: 1)
      optional(:per_page).filled(:integer, gteq?: 1, lteq?: 100)
      optional(:search).maybe(:string)
    end

    search_with do
      { items: model_class.all }
    end
  end
end
```

### Use in Controller

```ruby
class ProductsController < ApplicationController
  def index
    result = Product::IndexService.new(current_user, params: params).call

    render json: {
      products: result[:items],
      message: result[:message]
    }
  rescue BetterService::Errors::Runtime::ValidationError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
```

### Generate Complete CRUD

```bash
rails g serviceable:scaffold Product --cache --authorize
```

Creates all 5 CRUD services with cache and authorization.

### Add Validation

```ruby
class Product::CreateService < BetterService::CreateService
  schema do
    required(:name).filled(:string, min_size?: 3)
    required(:price).filled(:decimal, gt?: 0)
    optional(:description).maybe(:string)
  end

  process_with do |data|
    { resource: Product.create!(params) }
  end
end
```

### Add Authorization

```ruby
class Product::DestroyService < BetterService::DestroyService
  authorize_with do
    product = Product.find(params[:id])
    user.admin? || product.user_id == user.id
  end

  search_with do
    { resource: Product.find(params[:id]) }
  end

  process_with do |data|
    data[:resource].destroy!
    { resource: data[:resource] }
  end
end
```

## Critical Rules

### ✅ ALWAYS Use DSL Methods

```ruby
# ✅ CORRECT
class MyService < BetterService::CreateService
  process_with do |data|
    # Your logic
  end
end

# ❌ WRONG - Never override methods
class MyService < BetterService::CreateService
  def process(data)  # ❌ DON'T DO THIS
    # Your logic
  end
end
```

### ✅ NEVER Call Services from Services

```ruby
# ❌ WRONG
class Order::CreateService < BetterService::CreateService
  process_with do |data|
    order = Order.create!(params)
    Payment::ChargeService.new(user, params: {}).call  # ❌ DON'T
  end
end

# ✅ CORRECT - Use Workflow
class Order::CheckoutWorkflow < BetterService::Workflow
  step :create_order, with: Order::CreateService
  step :charge_payment, with: Payment::ChargeService
end
```

## Next Steps

- **Service Examples**: See `02-07` for detailed examples of each service type
- **Validation**: See `08-schema-validation.md` for validation patterns
- **Authorization**: See `09-authorization.md` for access control
- **Transactions**: See `10-transactions.md` for transaction management
- **Caching**: See `11-cache-management.md` for performance optimization
- **Presenters**: See `12-presenters.md` for output formatting
