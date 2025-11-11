# Generators Overview

## Introduction

BetterService provides Rails generators to quickly scaffold services and workflows. These generators create properly structured service files with common patterns and best practices built-in.

## Available Generators

### Service Generators (6)

Generate individual service types:

```bash
rails g serviceable:index ModelName
rails g serviceable:show ModelName
rails g serviceable:create ModelName
rails g serviceable:update ModelName
rails g serviceable:destroy ModelName
rails g serviceable:action ModelName ActionName
```

### Workflow Generator (1)

Generate workflow orchestration:

```bash
rails g serviceable:workflow WorkflowName
```

### Scaffold Generator (1)

Generate complete CRUD service set:

```bash
rails g serviceable:scaffold ModelName
```

## Quick Start

### Generate a Single Service

```bash
# Generate an IndexService for Product
rails g serviceable:index Product

# Creates: app/services/product/index_service.rb
```

### Generate Multiple Services

```bash
# Generate all CRUD services for Product
rails g serviceable:scaffold Product

# Creates:
#   app/services/product/index_service.rb
#   app/services/product/show_service.rb
#   app/services/product/create_service.rb
#   app/services/product/update_service.rb
#   app/services/product/destroy_service.rb
```

### Generate a Workflow

```bash
# Generate an order checkout workflow
rails g serviceable:workflow Order::Checkout

# Creates: app/workflows/order/checkout_workflow.rb
```

## Generator Options

All generators support common options:

### --cache

Enable cache configuration:

```bash
rails g serviceable:index Product --cache
```

Generates:

```ruby
module Product
  class IndexService < BetterService::IndexService
    model_class Product
    cache_contexts :products  # Added

    # ...
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
    presenter ProductPresenter  # Added

    # ...
  end
end
```

### --authorize

Add authorization block:

```bash
rails g serviceable:update Product --authorize
```

Generates:

```ruby
module Product
  class UpdateService < BetterService::UpdateService
    model_class Product

    authorize_with do
      resource = model_class.find(params[:id])
      user.admin? || resource.user_id == user.id
    end

    # ...
  end
end
```

### --namespace

Generate in a namespace:

```bash
rails g serviceable:index Admin::Product
```

Generates:

```ruby
module Admin
  module Product
    class IndexService < BetterService::IndexService
      model_class Admin::Product
      # ...
    end
  end
end

# File: app/services/admin/product/index_service.rb
```

## Common Patterns

### Pattern 1: Complete CRUD with Cache

```bash
rails g serviceable:scaffold Product --cache
```

Generates all 5 CRUD services with caching enabled.

### Pattern 2: Custom Action with Authorization

```bash
rails g serviceable:action Order Approve --authorize --cache
```

Generates:

```ruby
module Order
  class ApproveService < BetterService::ActionService
    model_class Order
    action_name :approve
    cache_contexts :orders

    authorize_with do
      resource = model_class.find(params[:id])
      user.admin? || resource.user_id == user.id
    end

    # ...
  end
end
```

### Pattern 3: Admin Namespace

```bash
rails g serviceable:scaffold Admin::Product --authorize --cache
```

Creates complete CRUD in `app/services/admin/product/` with authorization and caching.

## File Structure

### Service Files

```
app/
└── services/
    └── product/
        ├── index_service.rb
        ├── show_service.rb
        ├── create_service.rb
        ├── update_service.rb
        ├── destroy_service.rb
        └── approve_service.rb (custom action)
```

### Workflow Files

```
app/
└── workflows/
    └── order/
        └── checkout_workflow.rb
```

### Namespaced Services

```
app/
└── services/
    └── admin/
        └── product/
            ├── index_service.rb
            ├── create_service.rb
            └── update_service.rb
```

## Generator Templates

All generators use templates that follow BetterService best practices:

### Standard Template Structure

```ruby
module ModelName
  class ServiceTypeService < BetterService::ServiceType
    model_class ModelName

    # Cache (if --cache)
    cache_contexts :context_name

    # Presenter (if --presenter)
    presenter PresenterName

    # Schema
    schema do
      # Type-specific schema
    end

    # Authorization (if --authorize)
    authorize_with do
      # Type-specific authorization
    end

    # Search
    search_with do
      # Type-specific search
    end

    # Process
    process_with do |data|
      # Type-specific processing
    end
  end
end
```

## Customizing Generators

### Create Custom Templates

You can override default templates by creating files in:

```
lib/templates/serviceable/
├── index/
│   └── index_service.rb.tt
├── show/
│   └── show_service.rb.tt
└── create/
    └── create_service.rb.tt
```

Example custom template:

```ruby
# lib/templates/serviceable/index/index_service.rb.tt
module <%= class_path.map(&:camelize).join('::') %>
  class IndexService < BetterService::IndexService
    model_class <%= class_name %>

    # Your custom additions here

    schema do
      # Your default schema
    end

    search_with do
      { items: model_class.all }
    end
  end
end
```

## Next Steps

- **Service Generators**: [Detailed service generator documentation](02_service_generators.md)
- **Workflow Generator**: [Workflow generator guide](03_workflow_generator.md)
- **Service Types**: [Learn about each service type](../services/01_services_structure.md)

---

**See also:**
- [Getting Started](../getting-started.md)
- [Services Structure](../services/01_services_structure.md)
- [Workflows Introduction](../workflows/01_workflows_introduction.md)
