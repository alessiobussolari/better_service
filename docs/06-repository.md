# Repository Pattern

Learn how to use repositories for data access in BetterService.

---

## What is the Repository Pattern?

### Purpose

Repositories abstract data access from services.

```ruby
# Without repository - service knows ActiveRecord details
process_with do |data|
  Product.create!(params)
end

# With repository - service uses abstraction
process_with do |data|
  product_repository.create!(params)
end
```

--------------------------------

## Getting Started

### Generate with Base Service

Generate a repository with the base generator.

```bash
rails g serviceable:base Product
```

This creates:
- `app/services/product/base_service.rb`
- `app/repositories/product_repository.rb`
- `config/locales/product_services.en.yml`

--------------------------------

### Generated Repository

The generated repository class.

```ruby
# app/repositories/product_repository.rb
class ProductRepository < BetterService::Repository::BaseRepository
  # All BaseRepository methods are available
  # Add custom methods below
end
```

--------------------------------

### Configure BaseService

Connect the repository to your services.

```ruby
class Product::BaseService < BetterService::Services::Base
  include BetterService::Concerns::Serviceable::RepositoryAware

  messages_namespace :products
  cache_contexts [:products]
  repository :product  # Injects product_repository method
end
```

--------------------------------

## CRUD Operations

### Find Operations

Find records by ID or attributes.

```ruby
# Find by ID (raises RecordNotFound)
product = product_repository.find(1)

# Find by ID (returns nil)
product = product_repository.find_by(id: 1)

# Find by attributes
product = product_repository.find_by(name: "Widget", status: "active")

# Get all records
products = product_repository.all
```

--------------------------------

### Create Operation

Create new records.

```ruby
product = product_repository.create!(
  name: "Widget",
  price: 99.99,
  user: user
)
```

--------------------------------

### Update Operation

Update existing records.

```ruby
# Update with hash
product_repository.update!(product, name: "New Name", price: 149.99)

# Update from params
product_repository.update!(product, params.except(:id))
```

--------------------------------

### Destroy Operation

Delete records.

```ruby
product_repository.destroy!(product)
```

--------------------------------

## Search Method

### Basic Search

Search with predicates.

```ruby
products = product_repository.search(
  { name_cont: "widget", status_eq: "active" },
  page: 1,
  per_page: 25
)
```

--------------------------------

### Search with Options

Full search options.

```ruby
products = product_repository.search(
  { category_id_eq: 5, price_lteq: 100 },
  page: 2,
  per_page: 10,
  includes: [:category, :variants],
  order: { created_at: :desc }
)
```

--------------------------------

## Predicates

### Equality Predicates

Compare for equality.

```ruby
# Equal
products = product_repository.search({ status_eq: "active" })

# Not equal
products = product_repository.search({ status_not_eq: "deleted" })
```

--------------------------------

### Comparison Predicates

Compare numeric values.

```ruby
# Greater than
products = product_repository.search({ price_gt: 100 })

# Greater than or equal
products = product_repository.search({ price_gteq: 100 })

# Less than
products = product_repository.search({ price_lt: 500 })

# Less than or equal
products = product_repository.search({ price_lteq: 500 })
```

--------------------------------

### String Predicates

Search text fields.

```ruby
# Contains
products = product_repository.search({ name_cont: "widget" })

# Starts with
products = product_repository.search({ name_start: "Pro" })

# Ends with
products = product_repository.search({ name_end: "Edition" })
```

--------------------------------

### Collection Predicates

Check against lists.

```ruby
# In list
products = product_repository.search({ status_in: ["active", "pending"] })

# Not in list
products = product_repository.search({ status_not_in: ["deleted", "archived"] })
```

--------------------------------

### Null Predicates

Check for null values.

```ruby
# Is null
products = product_repository.search({ deleted_at_null: true })

# Is not null
products = product_repository.search({ published_at_not_null: true })
```

--------------------------------

## Using in Services

### Index Service

Complete index with repository search.

```ruby
class Product::IndexService < Product::BaseService
  performed_action :listed

  schema do
    optional(:page).filled(:integer, gteq?: 1)
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
      per_page: 25,
      includes: [:category],
      order: { created_at: :desc }
    )

    { items: items }
  end

  process_with { |data| { items: data[:items] } }
  respond_with { |data| success_result(message("index.success"), data) }
end
```

--------------------------------

### Show Service

Find with repository.

```ruby
class Product::ShowService < Product::BaseService
  performed_action :showed

  schema do
    required(:id).filled(:integer)
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

  process_with { |data| { resource: data[:resource] } }
  respond_with { |data| success_result(message("show.success"), data) }
end
```

--------------------------------

### Create Service

Create with repository.

```ruby
class Product::CreateService < Product::BaseService
  performed_action :created
  with_transaction true

  schema do
    required(:name).filled(:string)
    required(:price).filled(:decimal, gt?: 0)
  end

  search_with { {} }

  process_with do |_data|
    product = product_repository.create!(
      name: params[:name],
      price: params[:price],
      user: user
    )
    { resource: product }
  end

  respond_with { |data| success_result(message("create.success"), data) }
end
```

--------------------------------

## Custom Methods

### Adding Custom Methods

Extend your repository with custom queries.

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

  # Eager loading
  def with_details(id)
    model_class
      .includes(:category, :variants, :reviews)
      .find(id)
  end

  # Bulk operation
  def publish_all(ids)
    model_class.where(id: ids).update_all(
      published: true,
      published_at: Time.current
    )
  end
end
```

--------------------------------

### Using Custom Methods

Use custom methods in services.

```ruby
class Product::FeaturedService < Product::BaseService
  performed_action :listed

  schema { }

  search_with do
    { items: product_repository.featured.limit(10) }
  end

  process_with { |data| { items: data[:items] } }
  respond_with { |data| success_result(message("featured.success"), data) }
end
```

--------------------------------

## Multiple Repositories

### Using Multiple Repositories

Declare multiple repositories in a service.

```ruby
class Order::CreateService < Order::BaseService
  repository :order
  repository :product
  repository :inventory

  process_with do |data|
    product = product_repository.find(params[:product_id])

    stock = inventory_repository.find_by(product_id: product.id)
    raise ExecutionError.new("Out of stock") if stock.quantity < params[:quantity]

    order = order_repository.create!(
      product: product,
      quantity: params[:quantity],
      user: user
    )

    inventory_repository.update!(
      stock,
      quantity: stock.quantity - params[:quantity]
    )

    { resource: order }
  end
end
```

--------------------------------

## Benefits

### Why Use Repositories?

Key advantages of the repository pattern.

```ruby
# 1. Testability - Easy to mock in tests
allow(product_repository).to receive(:find).and_return(mock_product)

# 2. Abstraction - Services don't know about ActiveRecord
# Change database implementation without changing services

# 3. Reusability - Share queries across services
# Define once in repository, use everywhere

# 4. Maintainability - All queries in one place
# Easy to find and optimize queries

# 5. Consistency - Standard interface
# All services use the same patterns
```

--------------------------------
