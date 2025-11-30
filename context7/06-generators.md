# Generators

Rails generators for rapid service, workflow, and infrastructure creation.

---

## Base Generator

### Generate BaseService with Repository

Create the foundation for a resource's services.

```bash
rails g serviceable:base Product
```

```ruby
# Generated files:
# app/services/product/base_service.rb
# app/repositories/product_repository.rb
# config/locales/product_services.en.yml
# test/services/product/base_service_test.rb
# test/repositories/product_repository_test.rb

# Options:
# --skip_repository  # Skip repository generation
# --skip_locale      # Skip locale file
# --skip_test        # Skip test files
```

--------------------------------

### Generated BaseService

The generated BaseService file structure.

```ruby
class Product::BaseService < BetterService::Services::Base
  include BetterService::Concerns::Serviceable::RepositoryAware

  messages_namespace :products
  cache_contexts [:products]
  repository :product
end
```

--------------------------------

## Scaffold Generator

### Generate All CRUD Services

Create BaseService and all 5 CRUD services at once.

```bash
rails g serviceable:scaffold Product --base
```

```ruby
# Generated files:
# app/services/product/base_service.rb
# app/services/product/index_service.rb
# app/services/product/show_service.rb
# app/services/product/create_service.rb
# app/services/product/update_service.rb
# app/services/product/destroy_service.rb
# app/repositories/product_repository.rb
# config/locales/product_services.en.yml
# test/services/product/*_service_test.rb

# Options:
# --base             # Generate BaseService (recommended)
# --presenter        # Generate presenter class
# --skip_repository  # Skip repository
# --skip_locale      # Skip locale file
# --skip_test        # Skip test files
```

--------------------------------

### With Presenter

Generate scaffold with presenter class.

```bash
rails g serviceable:scaffold Product --base --presenter
```

--------------------------------

## Individual Service Generators

### Index Service

Generate an Index service.

```bash
rails g serviceable:index Product
rails g serviceable:index Product --base_class=Product::BaseService
```

--------------------------------

### Show Service

Generate a Show service.

```bash
rails g serviceable:show Product
rails g serviceable:show Product --base_class=Product::BaseService
```

--------------------------------

### Create Service

Generate a Create service.

```bash
rails g serviceable:create Product
rails g serviceable:create Product --base_class=Product::BaseService
```

--------------------------------

### Update Service

Generate an Update service.

```bash
rails g serviceable:update Product
rails g serviceable:update Product --base_class=Product::BaseService
```

--------------------------------

### Destroy Service

Generate a Destroy service.

```bash
rails g serviceable:destroy Product
rails g serviceable:destroy Product --base_class=Product::BaseService
```

--------------------------------

## Action Generator

### Custom Action Service

Generate a custom action service.

```bash
rails g serviceable:action Product publish
rails g serviceable:action Product approve --base_class=Product::BaseService
```

```ruby
# Generated file: app/services/product/publish_service.rb

class Product::PublishService < Product::BaseService
  performed_action :published
  with_transaction true
  auto_invalidate_cache true

  schema do
    required(:id).filled(:integer)
  end

  authorize_with do
    next true if user.admin?
    # Add authorization logic
    true
  end

  search_with do
    { resource: product_repository.find(params[:id]) }
  end

  process_with do |data|
    resource = data[:resource]
    # Add publish logic
    { resource: resource }
  end

  respond_with do |data|
    success_result(message("publish.success"), data)
  end
end
```

--------------------------------

## Workflow Generator

### Generate Workflow

Create a workflow for orchestrating services.

```bash
rails g serviceable:workflow Order::Purchase
rails g serviceable:workflow Subscription::Renewal
```

```ruby
# Generated file: app/workflows/order/purchase_workflow.rb

class Order::PurchaseWorkflow < BetterService::Workflows::Base
  with_transaction true

  # Define your workflow steps
  # step :validate, with: ValidateService
  # step :process, with: ProcessService
  # step :complete, with: CompleteService

  # Example with input mapping:
  # step :validate,
  #      with: Order::ValidateService,
  #      input: ->(ctx) { { order_id: ctx.order_id } }

  # Example with rollback:
  # step :charge,
  #      with: Payment::ChargeService,
  #      rollback: ->(ctx) { Payment::RefundService.new(ctx.user, params: { id: ctx.charge.id }).call }

  # Example with branching:
  # branch do
  #   on ->(ctx) { ctx.validate.express? } do
  #     step :express_shipping, with: Shipping::ExpressService
  #   end
  #   otherwise do
  #     step :standard_shipping, with: Shipping::StandardService
  #   end
  # end
end
```

--------------------------------

## Install Generator

### Setup BetterService

Initialize BetterService in your application.

```bash
rails g better_service:install
```

```ruby
# Generated files:
# config/initializers/better_service.rb
# config/locales/better_service.en.yml
```

--------------------------------

## Presenter Generator

### Generate Presenter

Create a presenter class for a resource.

```bash
rails g better_service:presenter Product
```

```ruby
# Generated file: app/presenters/product_presenter.rb

class ProductPresenter < BetterService::Presenter
  def as_json(options = {})
    {
      id: object.id,
      # Add more attributes
      created_at: object.created_at,
      updated_at: object.updated_at
    }
  end
end
```

--------------------------------

## Locale Generator

### Generate Locale File

Create a locale file for service messages.

```bash
rails g better_service:locale products
```

```yaml
# Generated file: config/locales/products_services.en.yml

en:
  products:
    services:
      index:
        success: "Products retrieved successfully"
      show:
        success: "Product retrieved successfully"
      create:
        success: "Product %{name} created successfully"
      update:
        success: "Product updated successfully"
      destroy:
        success: "Product deleted successfully"
```

--------------------------------

## Generator Options Summary

### Options Reference Table

Summary of all generator options.

```ruby
# Option             | Description              | Applies To
# -------------------|--------------------------|----------------
# --base             | Generate BaseService     | scaffold
# --base_class=Class | Custom parent class      | all services
# --presenter        | Generate presenter       | scaffold
# --skip_repository  | Skip repository          | base, scaffold
# --skip_locale      | Skip locale file         | base, scaffold
# --skip_test        | Skip test files          | all
```

--------------------------------

## Namespaced Resources

### Generate with Namespaces

All generators support namespaced resources.

```bash
rails g serviceable:base Admin::Product
rails g serviceable:scaffold Api::V1::Order --base
rails g serviceable:action Billing::Invoice send --base_class=Billing::Invoice::BaseService
rails g serviceable:workflow Admin::User::Onboarding
```

```ruby
# Generated structure for Admin::Product:
# app/services/admin/product/base_service.rb
# app/services/admin/product/index_service.rb
# app/repositories/admin/product_repository.rb
# config/locales/admin_product_services.en.yml
```

--------------------------------

## Complete Workflow Example

### Full Generation Sequence

Complete example of generating a resource's infrastructure.

```bash
# 1. Generate base infrastructure
rails g serviceable:base Product

# 2. Generate all CRUD services
rails g serviceable:scaffold Product --base --presenter

# 3. Add custom actions
rails g serviceable:action Product publish --base_class=Product::BaseService
rails g serviceable:action Product archive --base_class=Product::BaseService

# 4. Generate workflow for complex operation
rails g serviceable:workflow Product::BulkImport
```

--------------------------------

## Generated File Structure

### Complete Structure

File structure after running all generators for a resource.

```ruby
# app/
# ├── presenters/
# │   └── product_presenter.rb
# ├── repositories/
# │   └── product_repository.rb
# ├── services/
# │   └── product/
# │       ├── base_service.rb
# │       ├── index_service.rb
# │       ├── show_service.rb
# │       ├── create_service.rb
# │       ├── update_service.rb
# │       ├── destroy_service.rb
# │       ├── publish_service.rb
# │       └── archive_service.rb
# └── workflows/
#     └── product/
#         └── bulk_import_workflow.rb
#
# config/
# └── locales/
#     └── product_services.en.yml
#
# test/
# ├── presenters/
# │   └── product_presenter_test.rb
# ├── repositories/
# │   └── product_repository_test.rb
# ├── services/
# │   └── product/
# │       └── *_service_test.rb
# └── workflows/
#     └── product/
#         └── bulk_import_workflow_test.rb
```

--------------------------------
