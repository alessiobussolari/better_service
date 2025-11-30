# CRUD Services

Generate and customize full CRUD services for a resource.

---

## Using Generators

### Generate Everything at Once

The scaffold generator creates all CRUD services.

```bash
# Generate BaseService + all CRUD services
rails g serviceable:scaffold Product --base

# With presenter
rails g serviceable:scaffold Product --base --presenter

# What gets created:
# app/services/product/base_service.rb
# app/services/product/index_service.rb
# app/services/product/show_service.rb
# app/services/product/create_service.rb
# app/services/product/update_service.rb
# app/services/product/destroy_service.rb
# app/repositories/product_repository.rb
# config/locales/product_services.en.yml
```

--------------------------------

### Generate Base Only

Start with just the base infrastructure.

```bash
# Generate base service + repository + locale
rails g serviceable:base Product

# Creates:
# app/services/product/base_service.rb
# app/repositories/product_repository.rb
# config/locales/product_services.en.yml
```

--------------------------------

### Generate Individual Services

Add services one at a time.

```bash
# Generate specific services
rails g serviceable:index Product --base_class=Product::BaseService
rails g serviceable:show Product --base_class=Product::BaseService
rails g serviceable:create Product --base_class=Product::BaseService
rails g serviceable:update Product --base_class=Product::BaseService
rails g serviceable:destroy Product --base_class=Product::BaseService
```

--------------------------------

## Understanding BaseService

### The Foundation

BaseService centralizes common settings for all resource services.

```ruby
# app/services/product/base_service.rb
class Product::BaseService < BetterService::Services::Base
  include BetterService::Concerns::Serviceable::RepositoryAware

  # I18n namespace for messages
  messages_namespace :products

  # Cache context for invalidation
  cache_contexts [:products]

  # Inject repository helper method
  repository :product
end
```

--------------------------------

### Repository Integration

The repository provides data access methods.

```ruby
# app/repositories/product_repository.rb
class ProductRepository < BetterService::Repositories::Base
  model Product

  def published
    scope.where(published: true)
  end

  def by_user(user)
    scope.where(user: user)
  end
end

# In services, use product_repository
class Product::IndexService < Product::BaseService
  search_with do
    { items: product_repository.published.to_a }
  end
end
```

--------------------------------

## Index Service

### List Resources

The index service returns a collection.

```ruby
class Product::IndexService < Product::BaseService
  performed_action :listed

  schema do
    optional(:page).filled(:integer, gteq?: 1)
    optional(:per_page).filled(:integer, gteq?: 1, lteq?: 100)
    optional(:category).filled(:string)
  end

  authorize_with do
    true  # Anyone can list products
  end

  search_with do
    products = product_repository.all

    # Apply filters
    if params[:category]
      products = products.where(category: params[:category])
    end

    # Paginate
    page = params[:page] || 1
    per_page = params[:per_page] || 25
    products = products.page(page).per(per_page)

    { items: products.to_a, total: products.total_count }
  end

  respond_with do |data|
    success_result(message("index.success"), data)
  end
end
```

--------------------------------

## Show Service

### Find Single Resource

The show service finds and returns one record.

```ruby
class Product::ShowService < Product::BaseService
  performed_action :showed

  schema do
    required(:id).filled(:integer)
  end

  authorize_with do
    next true if user.admin?

    product = Product.find_by(id: params[:id])
    next false unless product

    # Public products visible to all, private only to owner
    product.published? || product.user_id == user.id
  end

  search_with do
    product = product_repository.find(params[:id])
    { resource: product }
  rescue ActiveRecord::RecordNotFound
    raise BetterService::Errors::Runtime::ResourceNotFoundError.new(
      "Product not found",
      context: { id: params[:id] }
    )
  end

  respond_with do |data|
    success_result(message("show.success"), data)
  end
end
```

--------------------------------

## Create Service

### Create New Resource

The create service handles record creation with transactions.

```ruby
class Product::CreateService < Product::BaseService
  performed_action :created
  with_transaction true

  schema do
    required(:name).filled(:string, min_size?: 2)
    required(:price).filled(:decimal, gt?: 0)
    optional(:description).filled(:string)
    optional(:category).filled(:string)
  end

  authorize_with do
    next true if user.admin?
    user.seller?  # Only sellers can create products
  end

  search_with do
    { context: { owner: user } }
  end

  process_with do |data|
    product = product_repository.create!(
      name: params[:name],
      price: params[:price],
      description: params[:description],
      category: params[:category],
      user: data[:context][:owner]
    )
    { resource: product }
  end

  respond_with do |data|
    success_result(
      message("create.success", name: data[:resource].name),
      data
    )
  end
end
```

--------------------------------

## Update Service

### Modify Existing Resource

The update service modifies an existing record.

```ruby
class Product::UpdateService < Product::BaseService
  performed_action :updated
  with_transaction true

  schema do
    required(:id).filled(:integer)
    optional(:name).filled(:string, min_size?: 2)
    optional(:price).filled(:decimal, gt?: 0)
    optional(:description).filled(:string)
    optional(:category).filled(:string)
  end

  authorize_with do
    next true if user.admin?

    product = Product.find_by(id: params[:id])
    next false unless product

    product.user_id == user.id  # Only owner can update
  end

  search_with do
    product = product_repository.find(params[:id])
    { resource: product }
  end

  process_with do |data|
    product = data[:resource]

    update_attrs = params.slice(:name, :price, :description, :category)
                        .compact

    product_repository.update!(product, update_attrs)
    { resource: product.reload }
  end

  respond_with do |data|
    success_result(
      message("update.success", name: data[:resource].name),
      data
    )
  end
end
```

--------------------------------

## Destroy Service

### Delete Resource

The destroy service removes a record.

```ruby
class Product::DestroyService < Product::BaseService
  performed_action :destroyed
  with_transaction true

  schema do
    required(:id).filled(:integer)
  end

  authorize_with do
    next true if user.admin?

    product = Product.find_by(id: params[:id])
    next false unless product

    product.user_id == user.id  # Only owner can delete
  end

  search_with do
    product = product_repository.find(params[:id])
    { resource: product }
  end

  process_with do |data|
    product = data[:resource]

    # Check business rules before deletion
    if product.orders.any?
      raise BetterService::Errors::Runtime::ExecutionError.new(
        "Cannot delete product with orders",
        context: { orders_count: product.orders.count }
      )
    end

    product_repository.destroy!(product)
    { resource: product }
  end

  respond_with do |data|
    success_result(
      message("destroy.success", name: data[:resource].name),
      data
    )
  end
end
```

--------------------------------

## Controller Integration

### Using CRUD Services

Wire services into your controller.

```ruby
class ProductsController < ApplicationController
  def index
    result = Product::IndexService.new(
      current_user,
      params: index_params
    ).call

    render json: { products: result.resource, meta: result.meta }
  end

  def show
    result = Product::ShowService.new(
      current_user,
      params: { id: params[:id].to_i }
    ).call

    render json: { product: result.resource }
  end

  def create
    result = Product::CreateService.new(
      current_user,
      params: product_params
    ).call

    if result.success?
      render json: { product: result.resource }, status: :created
    else
      render json: { error: result.message }, status: :unprocessable_entity
    end
  end

  private

  def index_params
    params.permit(:page, :per_page, :category).to_h.symbolize_keys
  end

  def product_params
    params.require(:product).permit(:name, :price, :description, :category)
          .to_h.symbolize_keys
  end
end
```

--------------------------------

## Custom Actions

### Add Non-CRUD Operations

Generate custom action services.

```bash
rails g serviceable:action Product publish --base_class=Product::BaseService
rails g serviceable:action Product archive --base_class=Product::BaseService
```

--------------------------------

### Implement Custom Action

Example publish service.

```ruby
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

    if product.published?
      raise BetterService::Errors::Runtime::ExecutionError.new(
        "Product is already published"
      )
    end

    product_repository.update!(product, published: true, published_at: Time.current)
    { resource: product.reload }
  end

  respond_with do |data|
    success_result("Product published successfully", data)
  end
end
```

--------------------------------

## I18n Messages

### Configure Locale File

Set up messages for your services.

```yaml
# config/locales/product_services.en.yml
en:
  products:
    services:
      index:
        success: "Products retrieved successfully"
      show:
        success: "Product found"
      create:
        success: "Product '%{name}' created successfully"
      update:
        success: "Product '%{name}' updated successfully"
      destroy:
        success: "Product '%{name}' deleted successfully"
      publish:
        success: "Product published successfully"
```

--------------------------------

## Next Steps

### Continue Learning

What to learn next.

```ruby
# Now that you understand CRUD services:

# 1. Master authorization patterns
#    → guide/03-authorization.md

# 2. Advanced validation
#    → guide/04-validation.md

# 3. Repository customization
#    → guide/05-repositories.md
```

--------------------------------
