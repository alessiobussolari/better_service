# Repository Pattern

The Repository pattern abstracts data access logic between services and ActiveRecord models.

---

## Setup

### Generate Repository with BaseService

Generate a BaseService with its associated Repository.

```bash
rails g serviceable:base Product
```

```ruby
# Generated files:
# - app/services/product/base_service.rb
# - app/repositories/product_repository.rb
# - config/locales/product_services.en.yml
```

--------------------------------

### BaseService Configuration

Configure the BaseService to use the repository.

```ruby
class Product::BaseService < BetterService::Services::Base
  include BetterService::Concerns::Serviceable::RepositoryAware

  messages_namespace :products
  cache_contexts [:products]
  repository :product  # Injects product_repository method
end
```

--------------------------------

### Repository Class

The generated repository inherits from BaseRepository.

```ruby
class ProductRepository < BetterService::Repository::BaseRepository
  # All BaseRepository methods available
  # Custom methods can be added here
end
```

--------------------------------

## BaseRepository Methods

### Basic CRUD Operations

Standard CRUD operations available in all repositories.

```ruby
# Find by ID (raises RecordNotFound if not found)
product = product_repository.find(1)

# Find by ID (returns nil if not found)
product = product_repository.find_by(id: 1)

# Find by attributes
product = product_repository.find_by(name: "Widget", status: "active")

# Get all records
products = product_repository.all

# Create record
product = product_repository.create!(name: "Widget", price: 99.99)

# Update record
product_repository.update!(product, name: "New Name")

# Destroy record
product_repository.destroy!(product)
```

--------------------------------

## Search with Predicates

### Basic Search

Search records using Ransack-like predicates.

```ruby
# Basic search
products = product_repository.search(
  { name_cont: "widget", status_eq: "active" },
  page: 1,
  per_page: 25
)

# With includes (eager loading)
products = product_repository.search(
  { category_id_eq: 5 },
  includes: [:category, :variants]
)

# With ordering
products = product_repository.search(
  { price_gteq: 100 },
  order: { created_at: :desc }
)

# Combined options
products = product_repository.search(
  { status_eq: "active", price_lteq: 500 },
  page: 2,
  per_page: 10,
  includes: [:category],
  order: { name: :asc }
)
```

--------------------------------

## Predicate Reference

### Available Predicates

Supported predicates for search queries.

```ruby
# Predicate       | SQL Equivalent     | Example
# ----------------|--------------------|--------------------------
# field_eq        | = value            | status_eq: "active"
# field_not_eq    | != value           | status_not_eq: "deleted"
# field_gt        | > value            | price_gt: 100
# field_gteq      | >= value           | price_gteq: 100
# field_lt        | < value            | price_lt: 500
# field_lteq      | <= value           | price_lteq: 500
# field_in        | IN (values)        | status_in: ["active", "pending"]
# field_not_in    | NOT IN (values)    | status_not_in: ["deleted"]
# field_cont      | LIKE %value%       | name_cont: "widget"
# field_start     | LIKE value%        | name_start: "Pro"
# field_end       | LIKE %value        | name_end: "Edition"
# field_null      | IS NULL            | deleted_at_null: true
# field_not_null  | IS NOT NULL        | published_at_not_null: true
```

--------------------------------

## Index Service with Repository

### Complete Index Example

Index service using repository search with filters.

```ruby
class Product::IndexService < Product::BaseService
  performed_action :listed

  schema do
    optional(:page).filled(:integer, gteq?: 1)
    optional(:per_page).filled(:integer, gteq?: 1, lteq?: 100)
    optional(:search).maybe(:string)
    optional(:category_id).maybe(:integer)
    optional(:min_price).maybe(:decimal)
    optional(:max_price).maybe(:decimal)
    optional(:status).maybe(:string)
  end

  search_with do
    predicates = {}

    # Text search
    predicates[:name_cont] = params[:search] if params[:search].present?

    # Exact match
    predicates[:category_id_eq] = params[:category_id] if params[:category_id]
    predicates[:status_eq] = params[:status] if params[:status]

    # Range filters
    predicates[:price_gteq] = params[:min_price] if params[:min_price]
    predicates[:price_lteq] = params[:max_price] if params[:max_price]

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

## Custom Repository Methods

### Extending the Repository

Add custom query methods to repositories.

```ruby
class ProductRepository < BetterService::Repository::BaseRepository
  # Custom finder
  def find_published(id)
    model_class.where(published: true).find(id)
  end

  # Custom scope
  def featured
    model_class.where(featured: true).order(created_at: :desc)
  end

  # Complex query
  def top_sellers(limit: 10)
    model_class
      .joins(:order_items)
      .group(:id)
      .order("COUNT(order_items.id) DESC")
      .limit(limit)
  end

  # With eager loading
  def with_full_details(id)
    model_class
      .includes(:category, :variants, :reviews)
      .find(id)
  end

  # Bulk operations
  def publish_all(ids)
    model_class.where(id: ids).update_all(published: true, published_at: Time.current)
  end
end
```

--------------------------------

## Multiple Repositories

### Using Multiple Repositories

Services can declare and use multiple repositories.

```ruby
class Order::CreateService < Order::BaseService
  repository :order
  repository :product
  repository :inventory

  process_with do |data|
    # Use product_repository
    product = product_repository.find(params[:product_id])

    # Check inventory
    stock = inventory_repository.find_by(product_id: product.id)
    raise ExecutionError.new("Out of stock") if stock.quantity < params[:quantity]

    # Create order with order_repository
    order = order_repository.create!(
      product: product,
      quantity: params[:quantity],
      user: user
    )

    # Update inventory
    inventory_repository.update!(stock, quantity: stock.quantity - params[:quantity])

    { resource: order }
  end
end
```

--------------------------------

## Benefits

### Repository Pattern Benefits

Key advantages of using the Repository pattern.

```ruby
# 1. Testability - Easy to mock repositories in tests
allow(product_repository).to receive(:find).and_return(mock_product)

# 2. Abstraction - Services don't know about ActiveRecord details
# Services call repository methods, not model methods directly

# 3. Reusability - Repository methods shared across services
# Define once in repository, use in multiple services

# 4. Maintainability - Database queries in one place
# All Product queries live in ProductRepository

# 5. Flexibility - Easy to switch data sources
# Change repository implementation without touching services
```

--------------------------------
