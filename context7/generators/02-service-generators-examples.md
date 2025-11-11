# Service Generators Examples

## Generate IndexService
Create a service for listing resources.

```bash
rails g serviceable:index Product
```

Creates: `app/services/product/index_service.rb`
```ruby
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

## Generate ShowService
Create a service for showing a single resource.

```bash
rails g serviceable:show Product
```

Creates: `app/services/product/show_service.rb`
```ruby
module Product
  class ShowService < BetterService::ShowService
    model_class Product

    schema do
      required(:id).filled(:integer)
    end

    search_with do
      { resource: model_class.find(params[:id]) }
    end
  end
end
```

## Generate CreateService
Create a service for resource creation.

```bash
rails g serviceable:create Product
```

Creates: `app/services/product/create_service.rb`
```ruby
module Product
  class CreateService < BetterService::CreateService
    model_class Product

    schema do
      required(:name).filled(:string)
      # Add your fields here
    end

    process_with do |data|
      resource = model_class.create!(params)
      { resource: resource }
    end
  end
end
```

## Generate with Cache
Add cache configuration automatically.

```bash
rails g serviceable:index Product --cache
```

Generates with cache enabled:
```ruby
module Product
  class IndexService < BetterService::IndexService
    model_class Product
    cache_contexts :products  # Added

    search_with do
      { items: model_class.all }
    end
  end
end
```

## Generate with Presenter
Add presenter configuration.

```bash
rails g serviceable:show Product --presenter=ProductPresenter
```

Generates with presenter:
```ruby
module Product
  class ShowService < BetterService::ShowService
    model_class Product
    presenter ProductPresenter  # Added

    search_with do
      { resource: model_class.find(params[:id]) }
    end
  end
end
```

## Generate with Authorization
Add authorization block.

```bash
rails g serviceable:destroy Product --authorize
```

Generates with authorization:
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

## Generate ActionService
Create a custom action service.

```bash
rails g serviceable:action Order Approve
```

Creates: `app/services/order/approve_service.rb`
```ruby
module Order
  class ApproveService < BetterService::ActionService
    model_class Order
    action_name :approve

    schema do
      required(:id).filled(:integer)
    end

    search_with do
      { resource: model_class.find(params[:id]) }
    end

    process_with do |data|
      resource = data[:resource]
      # Your custom business logic here
      { resource: resource }
    end
  end
end
```

## Generate Multiple Actions
Create multiple action services at once.

```bash
rails g serviceable:action Order Approve Cancel Refund
```

Creates three files:
- `app/services/order/approve_service.rb`
- `app/services/order/cancel_service.rb`
- `app/services/order/refund_service.rb`

## Generate Complete CRUD
Generate all 5 CRUD services at once.

```bash
rails g serviceable:scaffold Product
```

Creates:
- `app/services/product/index_service.rb`
- `app/services/product/show_service.rb`
- `app/services/product/create_service.rb`
- `app/services/product/update_service.rb`
- `app/services/product/destroy_service.rb`

## Scaffold with Options
Generate CRUD with all options.

```bash
rails g serviceable:scaffold Product --cache --authorize --presenter=ProductPresenter
```

All services generated with:
- Cache enabled
- Authorization blocks
- Presenter configuration

## Namespaced Services
Generate services in a namespace.

```bash
rails g serviceable:index Admin::Product
```

Creates: `app/services/admin/product/index_service.rb`
```ruby
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
