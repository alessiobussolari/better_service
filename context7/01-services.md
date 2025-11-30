# Services

Service architecture and DSL reference for BetterService.

---

## Service Architecture

### Inheritance Pattern

All services inherit from a resource-specific BaseService.

```ruby
# Inheritance chain
Product::CreateService < Product::BaseService < BetterService::Services::Base

# BaseService setup
class Product::BaseService < BetterService::Services::Base
  include BetterService::Concerns::Serviceable::RepositoryAware

  messages_namespace :products
  cache_contexts [:products]
  repository :product  # Injects product_repository method
end
```

--------------------------------

## DSL Reference

### Available DSL Methods

Complete list of service DSL methods and their purposes.

```ruby
# Method                          | Purpose                      | Default
# --------------------------------|------------------------------|--------
# performed_action :symbol        | Metadata action name         | Required
# with_transaction true/false     | Wrap process in transaction  | false
# auto_invalidate_cache true/false| Invalidate cache after write | true for writes
# schema do...end                 | Parameter validation         | Required
# authorize_with do...end         | Authorization check          | Optional
# search_with do...end            | Load data                    | Optional
# process_with do|data|...end     | Business logic               | Optional
# respond_with do|data|...end     | Format response              | Optional
# presenter PresenterClass        | Transform with presenter     | Optional
# messages_namespace :name        | I18n namespace               | Optional
# cache_contexts [:ctx1, :ctx2]   | Cache context keys           | Optional
# repository :model_name          | Repository dependency        | Optional
```

--------------------------------

## Phase 1: Validation

### Schema Definition

Define parameter validation using Dry::Schema syntax.

```ruby
schema do
  required(:name).filled(:string, min_size?: 2)
  required(:price).filled(:decimal, gt?: 0)
  optional(:published).maybe(:bool)
end

# Raises ValidationError with code: :validation_failed
```

--------------------------------

## Phase 2: Authorization

### Authorization Block

Check user permissions before executing business logic.

```ruby
authorize_with do
  next true if user.admin?  # Admin bypass FIRST
  product = Product.find_by(id: params[:id])
  next false unless product
  product.user_id == user.id
end

# Raises AuthorizationError with code: :unauthorized
```

--------------------------------

## Phase 3: Search

### Loading Data

Load required data in the search phase.

```ruby
search_with do
  product = product_repository.find(params[:id])
  { resource: product }
rescue ActiveRecord::RecordNotFound
  raise BetterService::Errors::Runtime::ResourceNotFoundError.new(
    "Product not found",
    context: { id: params[:id] }
  )
end
```

--------------------------------

## Phase 4: Process

### Business Logic

Transform data in the process phase.

```ruby
process_with do |data|
  product = data[:resource]
  product_repository.update!(product, params.except(:id))
  { resource: product.reload }
end
```

--------------------------------

## Phase 5: Respond

### Response Formatting

Format the final response using the respond_with block.

```ruby
respond_with do |data|
  success_result(message("update.success"), data)
end
```

--------------------------------

## Index Service

### Listing Resources

Complete Index service with filtering and pagination.

```ruby
class Product::IndexService < Product::BaseService
  performed_action :listed

  schema do
    optional(:page).filled(:integer, gteq?: 1)
    optional(:per_page).filled(:integer, gteq?: 1, lteq?: 100)
    optional(:search).maybe(:string)
    optional(:status).maybe(:string, included_in?: %w[active inactive])
  end

  search_with do
    predicates = {}
    predicates[:name_cont] = params[:search] if params[:search].present?
    predicates[:status_eq] = params[:status] if params[:status].present?

    items = product_repository.search(
      predicates,
      page: params[:page] || 1,
      per_page: params[:per_page] || 25
    )
    { items: items }
  end

  process_with do |data|
    { items: data[:items] }
  end

  respond_with do |data|
    success_result(message("index.success"), data)
  end
end
```

--------------------------------

## Show Service

### Finding a Resource

Complete Show service with authorization.

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
    product.published? || product.user_id == user.id
  end

  search_with do
    product = product_repository.find(params[:id])
    { resource: product }
  rescue ActiveRecord::RecordNotFound
    raise BetterService::Errors::Runtime::ResourceNotFoundError.new(
      "Product not found",
      context: { id: params[:id], model_class: "Product" }
    )
  end

  process_with do |data|
    { resource: data[:resource] }
  end

  respond_with do |data|
    success_result(message("show.success"), data)
  end
end
```

--------------------------------

## Create Service

### Creating a Resource

Complete Create service with transaction support.

```ruby
class Product::CreateService < Product::BaseService
  performed_action :created
  with_transaction true
  auto_invalidate_cache true

  schema do
    required(:name).filled(:string, min_size?: 2, max_size?: 100)
    required(:price).filled(:decimal, gt?: 0)
    optional(:description).maybe(:string)
    optional(:published).maybe(:bool)
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
      description: params[:description],
      published: params[:published] || false,
      user: user
    )
    { resource: product }
  rescue ActiveRecord::RecordInvalid => e
    raise BetterService::Errors::Runtime::DatabaseError.new(
      "Failed to create product",
      context: { errors: e.record.errors.to_hash },
      original_error: e
    )
  end

  respond_with do |data|
    success_result(message("create.success", name: data[:resource].name), data)
  end
end
```

--------------------------------

## Update Service

### Updating a Resource

Complete Update service with ownership check.

```ruby
class Product::UpdateService < Product::BaseService
  performed_action :updated
  with_transaction true
  auto_invalidate_cache true

  schema do
    required(:id).filled(:integer)
    optional(:name).filled(:string, min_size?: 2)
    optional(:price).filled(:decimal, gt?: 0)
    optional(:description).maybe(:string)
    optional(:published).maybe(:bool)
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
  rescue ActiveRecord::RecordNotFound
    raise BetterService::Errors::Runtime::ResourceNotFoundError.new(
      "Product not found",
      context: { id: params[:id] }
    )
  end

  process_with do |data|
    product = data[:resource]
    update_params = params.except(:id).compact
    product_repository.update!(product, update_params)
    { resource: product.reload }
  end

  respond_with do |data|
    success_result(message("update.success"), data)
  end
end
```

--------------------------------

## Destroy Service

### Deleting a Resource

Complete Destroy service with ownership check.

```ruby
class Product::DestroyService < Product::BaseService
  performed_action :destroyed
  with_transaction true
  auto_invalidate_cache true

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
  rescue ActiveRecord::RecordNotFound
    raise BetterService::Errors::Runtime::ResourceNotFoundError.new(
      "Product not found",
      context: { id: params[:id] }
    )
  end

  process_with do |data|
    product = data[:resource]
    product_repository.destroy!(product)
    { resource: product }
  end

  respond_with do |data|
    success_result(message("destroy.success"), data)
  end
end
```

--------------------------------

## Custom Action Service

### Custom Business Action

Service for custom actions like publish, archive, etc.

```ruby
class Product::PublishService < Product::BaseService
  performed_action :published
  with_transaction true
  auto_invalidate_cache true

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
  rescue ActiveRecord::RecordNotFound
    raise BetterService::Errors::Runtime::ResourceNotFoundError.new(
      "Product not found",
      context: { id: params[:id] }
    )
  end

  process_with do |data|
    product = data[:resource]

    if product.published?
      raise BetterService::Errors::Runtime::ExecutionError.new(
        "Product is already published",
        context: { id: product.id }
      )
    end

    product_repository.update!(product, published: true, published_at: Time.current)
    { resource: product.reload }
  end

  respond_with do |data|
    success_result(message("publish.success", name: data[:resource].name), data)
  end
end
```

--------------------------------

## Available Methods in DSL Blocks

### Accessing Service Data

Methods available inside DSL blocks.

```ruby
# Inside any DSL block you have access to:
user              # The user passed to initialize
params            # Validated parameters hash
product_repository # Repository instance (if declared)
message(key, **interpolations) # I18n message helper
success_result(message, data)  # Build success Result
```

--------------------------------
