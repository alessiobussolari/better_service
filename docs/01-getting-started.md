# Getting Started

Install BetterService and create your first service.

---

## Installation

### Add to Gemfile

Add BetterService to your Rails application.

```ruby
gem 'better_service'
```

```bash
bundle install
```

--------------------------------

### Run Install Generator

Generate the configuration files.

```bash
rails g better_service:install
```

This creates:
- `config/initializers/better_service.rb` - Configuration
- `config/locales/better_service.en.yml` - Default messages

--------------------------------

## Your First Service

### Generate a Complete Service Stack

Use the scaffold generator to create all CRUD services.

```bash
# Generate BaseService + Repository + all CRUD services
rails g serviceable:scaffold Product --base
```

This creates:
- `app/services/product/base_service.rb`
- `app/services/product/index_service.rb`
- `app/services/product/show_service.rb`
- `app/services/product/create_service.rb`
- `app/services/product/update_service.rb`
- `app/services/product/destroy_service.rb`
- `app/repositories/product_repository.rb`
- `config/locales/product_services.en.yml`

--------------------------------

### Understanding the BaseService

The generated BaseService is the foundation for all Product services.

```ruby
class Product::BaseService < BetterService::Services::Base
  include BetterService::Concerns::Serviceable::RepositoryAware

  messages_namespace :products    # I18n namespace
  cache_contexts [:products]      # Cache invalidation context
  repository :product             # Injects product_repository method
end
```

--------------------------------

### A Simple Create Service

Here's what the generated CreateService looks like.

```ruby
class Product::CreateService < Product::BaseService
  performed_action :created
  with_transaction true

  schema do
    required(:name).filled(:string)
    required(:price).filled(:decimal, gt?: 0)
  end

  authorize_with do
    next true if user.admin?
    user.seller?
  end

  search_with do
    {}
  end

  process_with do |_data|
    product = product_repository.create!(
      name: params[:name],
      price: params[:price],
      user: user
    )
    { resource: product }
  end

  respond_with do |data|
    success_result(message("create.success", name: data[:resource].name), data)
  end
end
```

--------------------------------

## Using Services in Controllers

### Basic Controller Pattern

Use services in your controllers.

```ruby
class ProductsController < ApplicationController
  def index
    result = Product::IndexService.new(current_user, params: index_params).call

    if result.success?
      render json: { products: result.resource }
    else
      render json: { error: result.message }, status: :unprocessable_entity
    end
  end

  def create
    result = Product::CreateService.new(current_user, params: product_params).call

    if result.success?
      render json: { product: result.resource, message: result.message }, status: :created
    else
      render json: { error: result.message }, status: :unprocessable_entity
    end
  rescue BetterService::Errors::Runtime::ValidationError => e
    render json: { errors: e.context[:validation_errors] }, status: :unprocessable_entity
  end

  private

  def index_params
    params.permit(:page, :per_page, :search)
  end

  def product_params
    params.require(:product).permit(:name, :price, :description)
  end
end
```

--------------------------------

## Service Lifecycle

### The 5-Phase Flow

Every service executes through 5 phases.

```ruby
# 1. VALIDATION (during initialize)
#    Schema validation happens automatically
#    Raises ValidationError if params are invalid

# 2. AUTHORIZATION (during call)
#    authorize_with block is evaluated
#    Returns failure result if false

# 3. SEARCH (during call)
#    search_with block loads data
#    Returns { resource: obj } or { items: [...] }

# 4. PROCESS (during call)
#    process_with block transforms data
#    Must return { resource: obj }

# 5. RESPOND (during call)
#    respond_with block formats response
#    Returns BetterService::Result
```

--------------------------------

## Manual Service Creation

### Creating a Service Without Generator

Create services manually if needed.

```ruby
# app/services/product/publish_service.rb
class Product::PublishService < Product::BaseService
  performed_action :published
  with_transaction true

  schema do
    required(:id).filled(:integer)
  end

  authorize_with do
    next true if user.admin?
    product = Product.find_by(id: params[:id])
    next false unless product
    product.user_id == user.id
  end

  search_with do
    product = product_repository.find(params[:id])
    { resource: product }
  end

  process_with do |data|
    product = data[:resource]
    product_repository.update!(product, published: true)
    { resource: product.reload }
  end

  respond_with do |data|
    success_result(message("publish.success"), data)
  end
end
```

--------------------------------

## Next Steps

### Where to Go From Here

Continue learning BetterService:

1. **[Services Guide](02-services.md)** - Deep dive into service patterns
2. **[Validation](03-validation.md)** - Schema validation with Dry::Schema
3. **[Authorization](04-authorization.md)** - Permission patterns
4. **[Result Wrapper](05-result.md)** - Handling service responses
5. **[Workflows](07-workflows.md)** - Orchestrating multiple services

--------------------------------
