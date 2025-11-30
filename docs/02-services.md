# Services Guide

Learn how to build effective services with BetterService.

---

## Service Types

### CRUD Services

BetterService supports standard CRUD operations.

```ruby
# Index  - List resources    → performed_action :listed
# Show   - View a resource   → performed_action :showed
# Create - Create a resource → performed_action :created
# Update - Update a resource → performed_action :updated
# Destroy - Delete a resource → performed_action :destroyed
```

--------------------------------

### Custom Action Services

Create custom actions beyond CRUD.

```ruby
# Publish  → performed_action :published
# Archive  → performed_action :archived
# Approve  → performed_action :approved
# Duplicate → performed_action :duplicated
```

--------------------------------

## Service Structure

### Anatomy of a Service

Every service has these components.

```ruby
class Product::CreateService < Product::BaseService
  # Metadata
  performed_action :created
  with_transaction true
  auto_invalidate_cache true

  # Phase 1: Validation
  schema do
    required(:name).filled(:string)
    required(:price).filled(:decimal, gt?: 0)
  end

  # Phase 2: Authorization
  authorize_with do
    next true if user.admin?
    user.seller?
  end

  # Phase 3: Search
  search_with do
    {}  # No pre-loading needed for create
  end

  # Phase 4: Process
  process_with do |_data|
    product = product_repository.create!(params)
    { resource: product }
  end

  # Phase 5: Respond
  respond_with do |data|
    success_result(message("create.success"), data)
  end
end
```

--------------------------------

## DSL Configuration

### performed_action

Sets the action name in metadata.

```ruby
performed_action :created

# Result: result.meta[:action] => :created
```

--------------------------------

### with_transaction

Wraps process phase in a database transaction.

```ruby
with_transaction true  # Enable transaction
with_transaction false # Disable transaction (default)

# Recommended: Enable for Create, Update, Destroy
# Not needed for: Index, Show (read-only)
```

--------------------------------

### auto_invalidate_cache

Controls automatic cache invalidation after writes.

```ruby
auto_invalidate_cache true  # Invalidate cache after success
auto_invalidate_cache false # Manual cache control

# Default: true for write operations (Create/Update/Destroy)
```

--------------------------------

## Index Service

### Listing Resources

Complete Index service with search and pagination.

```ruby
class Product::IndexService < Product::BaseService
  performed_action :listed

  schema do
    optional(:page).filled(:integer, gteq?: 1)
    optional(:per_page).filled(:integer, gteq?: 1, lteq?: 100)
    optional(:search).maybe(:string)
    optional(:category_id).maybe(:integer)
  end

  search_with do
    predicates = {}
    predicates[:name_cont] = params[:search] if params[:search].present?
    predicates[:category_id_eq] = params[:category_id] if params[:category_id]

    items = product_repository.search(
      predicates,
      page: params[:page] || 1,
      per_page: params[:per_page] || 25,
      includes: [:category],
      order: { created_at: :desc }
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

### Finding a Single Resource

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
      message("show.not_found"),
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

Complete Create service with transaction.

```ruby
class Product::CreateService < Product::BaseService
  performed_action :created
  with_transaction true
  auto_invalidate_cache true

  schema do
    required(:name).filled(:string, min_size?: 2, max_size?: 100)
    required(:price).filled(:decimal, gt?: 0)
    optional(:description).maybe(:string, max_size?: 1000)
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
      message("show.not_found"),
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

Complete Destroy service with authorization.

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
      message("destroy.not_found"),
      context: { id: params[:id] }
    )
  end

  process_with do |data|
    product = data[:resource]

    if product.orders.any?
      raise BetterService::Errors::Runtime::ExecutionError.new(
        message("destroy.has_orders"),
        context: { id: product.id, orders_count: product.orders.count }
      )
    end

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

### Publishing a Product

Custom action example.

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
  end

  process_with do |data|
    product = data[:resource]

    if product.published?
      raise BetterService::Errors::Runtime::ExecutionError.new(
        message("publish.already_published"),
        context: { id: product.id }
      )
    end

    unless product.ready_for_publish?
      raise BetterService::Errors::Runtime::ExecutionError.new(
        message("publish.not_ready"),
        context: { id: product.id, missing: product.missing_requirements }
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

## Best Practices

### Service Design Guidelines

Follow these guidelines for effective services.

```ruby
# 1. One responsibility per service
# GOOD: Product::PublishService does ONE thing
# BAD: Product::PublishAndNotifyService does TOO MUCH

# 2. Use workflows for multi-step operations
# GOOD: PublishWorkflow with separate services
# BAD: One service calling other services

# 3. Keep authorization simple
# Check admin first, then specific permissions

# 4. Use transactions for write operations
# Create, Update, Destroy should use with_transaction true

# 5. Handle errors explicitly
# Catch specific exceptions, provide context
```

--------------------------------
