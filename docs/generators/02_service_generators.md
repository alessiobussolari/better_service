# Service Generators

## Overview

BetterService provides 7 service generators: 5 for standard CRUD operations, 1 for custom actions, and 1 scaffold generator for complete CRUD sets.

## Index Generator

### Command

```bash
rails g serviceable:index ModelName [options]
```

### Generated File

```ruby
# app/services/model_name/index_service.rb
module ModelName
  class IndexService < BetterService::IndexService
    model_class ModelName

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

### Options

```bash
# With cache
rails g serviceable:index Product --cache

# With presenter
rails g serviceable:index Product --presenter=ProductPresenter

# Combined options
rails g serviceable:index Product --cache --presenter=ProductPresenter
```

### Example Usage

```bash
$ rails g serviceable:index Product --cache

create  app/services/product/index_service.rb
```

```ruby
# app/services/product/index_service.rb
module Product
  class IndexService < BetterService::IndexService
    model_class Product
    cache_contexts :products

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

---

## Show Generator

### Command

```bash
rails g serviceable:show ModelName [options]
```

### Generated File

```ruby
# app/services/model_name/show_service.rb
module ModelName
  class ShowService < BetterService::ShowService
    model_class ModelName

    schema do
      required(:id).filled(:integer)
    end

    search_with do
      resource = model_class.find(params[:id])
      { resource: resource }
    end
  end
end
```

### Options

```bash
# With cache and presenter
rails g serviceable:show Product --cache --presenter=ProductPresenter

# With authorization
rails g serviceable:show Product --authorize --cache
```

### Example Usage

```bash
$ rails g serviceable:show Product --authorize --cache

create  app/services/product/show_service.rb
```

```ruby
# app/services/product/show_service.rb
module Product
  class ShowService < BetterService::ShowService
    model_class Product
    cache_contexts :product

    schema do
      required(:id).filled(:integer)
    end

    authorize_with do
      resource = model_class.find(params[:id])
      user.admin? || resource.public? || resource.user_id == user.id
    end

    search_with do
      resource = model_class.find(params[:id])
      { resource: resource }
    end
  end
end
```

---

## Create Generator

### Command

```bash
rails g serviceable:create ModelName [options]
```

### Generated File

```ruby
# app/services/model_name/create_service.rb
module ModelName
  class CreateService < BetterService::CreateService
    model_class ModelName

    schema do
      # Add your required fields here
      required(:name).filled(:string)
    end

    search_with do
      {}
    end

    process_with do |data|
      resource = model_class.create!(params)
      { resource: resource }
    end
  end
end
```

### Options

```bash
# With cache invalidation
rails g serviceable:create Product --cache

# With authorization
rails g serviceable:create Product --authorize --cache
```

### Example Usage

```bash
$ rails g serviceable:create Product --cache --authorize

create  app/services/product/create_service.rb
```

```ruby
# app/services/product/create_service.rb
module Product
  class CreateService < BetterService::CreateService
    model_class Product
    cache_contexts :products

    schema do
      required(:name).filled(:string)
      required(:price).filled(:decimal, gt?: 0)
      optional(:description).maybe(:string)
    end

    authorize_with do
      user.admin? || user.has_permission?(:create_products)
    end

    search_with do
      {}
    end

    process_with do |data|
      resource = model_class.create!(params.merge(user: user))

      invalidate_cache_for(user)

      { resource: resource }
    end
  end
end
```

---

## Update Generator

### Command

```bash
rails g serviceable:update ModelName [options]
```

### Generated File

```ruby
# app/services/model_name/update_service.rb
module ModelName
  class UpdateService < BetterService::UpdateService
    model_class ModelName

    schema do
      required(:id).filled(:integer)
      optional(:name).maybe(:string)
    end

    search_with do
      resource = model_class.find(params[:id])
      { resource: resource }
    end

    process_with do |data|
      resource = data[:resource]
      resource.update!(params.except(:id))
      { resource: resource }
    end
  end
end
```

### Options

```bash
# With full options
rails g serviceable:update Product --cache --authorize --presenter=ProductPresenter
```

### Example Usage

```bash
$ rails g serviceable:update Product --cache --authorize

create  app/services/product/update_service.rb
```

```ruby
# app/services/product/update_service.rb
module Product
  class UpdateService < BetterService::UpdateService
    model_class Product
    cache_contexts :products, :product

    schema do
      required(:id).filled(:integer)
      optional(:name).maybe(:string)
      optional(:price).maybe(:decimal, gt?: 0)
      optional(:description).maybe(:string)
    end

    authorize_with do
      resource = model_class.find(params[:id])
      user.admin? || resource.user_id == user.id
    end

    search_with do
      resource = model_class.find(params[:id])
      { resource: resource }
    end

    process_with do |data|
      resource = data[:resource]
      resource.update!(params.except(:id))

      invalidate_cache_for(user)

      { resource: resource }
    end
  end
end
```

---

## Destroy Generator

### Command

```bash
rails g serviceable:destroy ModelName [options]
```

### Generated File

```ruby
# app/services/model_name/destroy_service.rb
module ModelName
  class DestroyService < BetterService::DestroyService
    model_class ModelName

    schema do
      required(:id).filled(:integer)
    end

    search_with do
      resource = model_class.find(params[:id])
      { resource: resource }
    end

    process_with do |data|
      resource = data[:resource]
      resource.destroy!
      { resource: resource }
    end
  end
end
```

### Options

```bash
# With authorization (highly recommended for destroy!)
rails g serviceable:destroy Product --authorize --cache
```

### Example Usage

```bash
$ rails g serviceable:destroy Product --authorize --cache

create  app/services/product/destroy_service.rb
```

```ruby
# app/services/product/destroy_service.rb
module Product
  class DestroyService < BetterService::DestroyService
    model_class Product
    cache_contexts :products

    schema do
      required(:id).filled(:integer)
      optional(:force).maybe(:bool)
    end

    authorize_with do
      resource = model_class.find(params[:id])
      user.admin? || resource.user_id == user.id
    end

    search_with do
      resource = model_class.includes(:reviews, :images).find(params[:id])

      # Check for dependencies
      if resource.orders.active.any? && !params[:force]
        raise BetterService::Errors::Runtime::ValidationError.new(
          "Cannot delete product with active orders"
        )
      end

      { resource: resource }
    end

    process_with do |data|
      resource = data[:resource]

      # Cleanup
      resource.images.purge_later
      resource.reviews.destroy_all

      # Delete
      resource.destroy!

      invalidate_cache_for(user)

      { resource: resource }
    end
  end
end
```

---

## Action Generator

### Command

```bash
rails g serviceable:action ModelName ActionName [options]
```

### Generated File

```ruby
# app/services/model_name/action_name_service.rb
module ModelName
  class ActionNameService < BetterService::ActionService
    model_class ModelName
    action_name :action_name

    schema do
      required(:id).filled(:integer)
    end

    search_with do
      resource = model_class.find(params[:id])
      { resource: resource }
    end

    process_with do |data|
      resource = data[:resource]

      # Your custom business logic here

      { resource: resource }
    end
  end
end
```

### Options

```bash
# Generate approval service
rails g serviceable:action Order Approve --authorize --cache --transaction

# Generate multiple actions
rails g serviceable:action Order Approve Cancel Refund --authorize
```

### Example Usage

```bash
$ rails g serviceable:action Order Approve --authorize --cache --transaction

create  app/services/order/approve_service.rb
```

```ruby
# app/services/order/approve_service.rb
module Order
  class ApproveService < BetterService::ActionService
    model_class Order
    action_name :approve
    cache_contexts :orders

    self._transactional = true

    schema do
      required(:id).filled(:integer)
      optional(:notes).maybe(:string)
    end

    authorize_with do
      resource = model_class.find(params[:id])
      user.manager? || user.admin?
    end

    search_with do
      order = model_class.includes(:items, :user).find(params[:id])

      unless order.pending?
        raise BetterService::Errors::Runtime::ValidationError.new(
          "Only pending orders can be approved"
        )
      end

      { resource: order }
    end

    process_with do |data|
      order = data[:resource]

      order.update!(
        status: 'approved',
        approved_at: Time.current,
        approved_by_id: user.id,
        approval_notes: params[:notes]
      )

      # Business logic
      order.items.each do |item|
        item.product.decrement!(:stock, item.quantity)
      end

      OrderMailer.approved(order).deliver_later

      invalidate_cache_for(user)
      invalidate_cache_for(order.user)

      { resource: order }
    end
  end
end
```

### Generating Multiple Actions

```bash
$ rails g serviceable:action Article Publish Archive Unpublish --authorize

create  app/services/article/publish_service.rb
create  app/services/article/archive_service.rb
create  app/services/article/unpublish_service.rb
```

---

## Scaffold Generator

### Command

```bash
rails g serviceable:scaffold ModelName [options]
```

Generates all 5 CRUD services at once.

### Generated Files

```bash
$ rails g serviceable:scaffold Product --cache --authorize

create  app/services/product/index_service.rb
create  app/services/product/show_service.rb
create  app/services/product/create_service.rb
create  app/services/product/update_service.rb
create  app/services/product/destroy_service.rb
```

Each file is generated with the same options applied.

### Example Usage

```bash
# Generate complete CRUD with all options
rails g serviceable:scaffold Product --cache --authorize --presenter=ProductPresenter
```

This creates:

1. **IndexService** - with cache, presenter
2. **ShowService** - with cache, authorize, presenter
3. **CreateService** - with cache, authorize
4. **UpdateService** - with cache, authorize, presenter
5. **DestroyService** - with cache, authorize

---

## Namespaced Generators

All generators support namespaces:

### Single Namespace

```bash
rails g serviceable:index Admin::Product
```

```ruby
# app/services/admin/product/index_service.rb
module Admin
  module Product
    class IndexService < BetterService::IndexService
      model_class Admin::Product

      # ...
    end
  end
end
```

### Multiple Namespaces

```bash
rails g serviceable:scaffold Api::V1::Product
```

```ruby
# app/services/api/v1/product/index_service.rb
module Api
  module V1
    module Product
      class IndexService < BetterService::IndexService
        model_class Api::V1::Product

        # ...
      end
    end
  end
end
```

---

## Generator Options Reference

### Global Options

| Option | Short | Description | Example |
|--------|-------|-------------|---------|
| `--cache` | `-c` | Add cache configuration | `--cache` |
| `--presenter` | `-p` | Add presenter | `--presenter=ProductPresenter` |
| `--authorize` | `-a` | Add authorization block | `--authorize` |
| `--namespace` | `-n` | Generate in namespace | `--namespace=Admin` |
| `--skip` | `-s` | Skip file if exists | `--skip` |
| `--force` | `-f` | Overwrite existing file | `--force` |

### ActionService-Specific Options

| Option | Description | Example |
|--------|-------------|---------|
| `--transaction` | Enable transactions | `--transaction` |
| `--no-transaction` | Disable transactions | `--no-transaction` |

### Examples

```bash
# All options
rails g serviceable:create Product \
  --cache \
  --presenter=ProductPresenter \
  --authorize

# Short form
rails g serviceable:create Product -c -p ProductPresenter -a

# Action with transaction
rails g serviceable:action Payment Process --transaction --authorize

# Scaffold with all options
rails g serviceable:scaffold Product --cache --authorize --presenter=ProductPresenter
```

---

## Best Practices

### 1. Always Use Authorization for Write Operations

```bash
# ✅ Good
rails g serviceable:create Product --authorize
rails g serviceable:update Product --authorize
rails g serviceable:destroy Product --authorize

# ⚠️  Use with caution (public endpoints)
rails g serviceable:create Product
```

### 2. Enable Cache for Read Operations

```bash
# ✅ Good
rails g serviceable:index Product --cache
rails g serviceable:show Product --cache
```

### 3. Use Presenters for Consistent Output

```bash
# ✅ Good
rails g serviceable:show Product --presenter=ProductPresenter --cache
```

### 4. Scaffold for Complete CRUD

```bash
# ✅ Good - generates all services with same options
rails g serviceable:scaffold Product --cache --authorize --presenter=ProductPresenter

# ❌ Less efficient - generates one by one
rails g serviceable:index Product --cache
rails g serviceable:show Product --cache
# ... etc
```

### 5. Use Transaction for ActionServices That Write

```bash
# ✅ Good - write operation
rails g serviceable:action Order Approve --transaction --authorize

# ✅ Good - read operation
rails g serviceable:action Report Generate --no-transaction
```

---

## Common Workflows

### Setting Up a New Resource

```bash
# 1. Generate model
rails g model Product name:string price:decimal description:text

# 2. Generate presenter
rails g presenter Product

# 3. Generate complete service set
rails g serviceable:scaffold Product \
  --cache \
  --authorize \
  --presenter=ProductPresenter

# 4. Generate custom actions
rails g serviceable:action Product Publish Archive --authorize

# 5. Migrate
rails db:migrate
```

### Adding Services to Existing Resource

```bash
# Add just what you need
rails g serviceable:index Product --cache --presenter=ProductPresenter
rails g serviceable:create Product --authorize --cache
```

### Admin Namespace Setup

```bash
# Generate admin CRUD
rails g serviceable:scaffold Admin::Product \
  --authorize \
  --cache \
  --presenter=Admin::ProductPresenter
```

---

**See also:**
- [Generators Overview](01_generators_overview.md)
- [Workflow Generator](03_workflow_generator.md)
- [Services Structure](../services/01_services_structure.md)
