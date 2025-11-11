# Generators Overview

## What are Generators?

BetterService provides Rails generators to quickly scaffold services and workflows with proper structure and conventions.

## Available Generators

### Service Generators

Generate individual service types:

```bash
# IndexService
rails g serviceable:index Product

# ShowService
rails g serviceable:show Product

# CreateService
rails g serviceable:create Product

# UpdateService
rails g serviceable:update Product

# DestroyService
rails g serviceable:destroy Product

# ActionService
rails g serviceable:action Order Approve
```

### Workflow Generator

Generate workflows:

```bash
rails g serviceable:workflow Order::Checkout
```

### Scaffold Generator

Generate complete CRUD set (all 5 services):

```bash
rails g serviceable:scaffold Product
```

## Generator Options

### --cache

Enable caching for the service:

```bash
rails g serviceable:index Product --cache
```

Generates:
```ruby
module Product
  class IndexService < BetterService::IndexService
    model_class Product
    cache_contexts :products  # Added automatically

    search_with do
      { items: model_class.all }
    end
  end
end
```

### --presenter

Add presenter configuration:

```bash
rails g serviceable:show Product --presenter=ProductPresenter
```

Generates:
```ruby
module Product
  class ShowService < BetterService::ShowService
    model_class Product
    presenter ProductPresenter  # Added automatically

    search_with do
      { resource: model_class.find(params[:id]) }
    end
  end
end
```

### --authorize

Add authorization block:

```bash
rails g serviceable:destroy Product --authorize
```

Generates:
```ruby
module Product
  class DestroyService < BetterService::DestroyService
    model_class Product

    authorize_with do
      resource = model_class.find(params[:id])
      user.admin? || resource.user_id == user.id
    end

    search_with do
      { resource: model_class.find(params[:id]) }
    end

    process_with do |data|
      data[:resource].destroy!
      { resource: data[:resource] }
    end
  end
end
```

### Combining Options

```bash
rails g serviceable:scaffold Product --cache --authorize --presenter=ProductPresenter
```

All generated services will include:
- Cache configuration
- Authorization blocks
- Presenter setup

## File Locations

Generators create files in standard Rails locations:

```
app/
├── services/
│   └── product/
│       ├── index_service.rb
│       ├── show_service.rb
│       ├── create_service.rb
│       ├── update_service.rb
│       └── destroy_service.rb
└── workflows/
    └── order/
        └── checkout_workflow.rb
```

## Namespaced Generators

Generate services in nested modules:

```bash
rails g serviceable:index Admin::Product
```

Creates:
```ruby
# app/services/admin/product/index_service.rb
module Admin
  module Product
    class IndexService < BetterService::IndexService
      model_class Admin::Product

      search_with do
        { items: model_class.all }
      end
    end
  end
end
```

## Quick Start Examples

### Basic CRUD

```bash
# Generate all CRUD services
rails g serviceable:scaffold Product

# Use in controller
class ProductsController < ApplicationController
  def index
    result = Product::IndexService.new(current_user, params: params).call
    @products = result[:items]
  end

  def show
    result = Product::ShowService.new(current_user, params: { id: params[:id] }).call
    @product = result[:resource]
  end

  def create
    result = Product::CreateService.new(current_user, params: product_params).call
    redirect_to product_path(result[:resource])
  end
end
```

### Custom Actions

```bash
# Generate multiple custom actions
rails g serviceable:action Order Approve Cancel Refund
```

Creates:
- `app/services/order/approve_service.rb`
- `app/services/order/cancel_service.rb`
- `app/services/order/refund_service.rb`

### Complete Workflow

```bash
# Generate workflow
rails g serviceable:workflow Order::Checkout
```

Then configure:
```ruby
module Order
  class CheckoutWorkflow < BetterService::Workflow
    schema do
      required(:cart_id).filled(:integer)
    end

    step :create_order, with: Order::CreateService
    step :charge_payment, with: Payment::ChargeService
    step :send_confirmation, with: Email::ConfirmationService
  end
end
```

## Next Steps

- **Service Generator Examples**: See `02-service-generators-examples.md`
- **Workflow Generator Examples**: See `03-workflow-generator-examples.md`
