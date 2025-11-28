# Repository Pattern Guide

BetterService provides a Repository Pattern implementation for abstracting data access from your services. This promotes testability, separation of concerns, and cleaner service code.

## Table of Contents

- [Overview](#overview)
- [BaseRepository](#baserepository)
- [RepositoryAware Concern](#repositoryaware-concern)
- [Custom Repositories](#custom-repositories)
- [Predicates and Search](#predicates-and-search)
- [Testing with Repositories](#testing-with-repositories)
- [Best Practices](#best-practices)

---

## Overview

### What is the Repository Pattern?

The Repository Pattern provides an abstraction layer between your business logic (services) and data access (ActiveRecord models). It encapsulates all database queries in dedicated repository classes.

### Benefits

| Benefit | Description |
|---------|-------------|
| **Testability** | Mock repositories for fast unit tests without database |
| **Reusability** | Share query logic across multiple services |
| **Maintainability** | Change data access in one place |
| **Separation** | Keep services focused on business logic |
| **Encapsulation** | Hide complex queries behind simple methods |

### Architecture

```
Controller
    │
    ▼
┌─────────────────────────────────────┐
│           Service Layer             │
│  ┌─────────────────────────────┐   │
│  │  include RepositoryAware    │   │
│  │  repository :product        │   │
│  │                             │   │
│  │  search_with do             │   │
│  │    product_repository.      │   │
│  │      published.to_a         │   │
│  │  end                        │   │
│  └─────────────────────────────┘   │
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│         Repository Layer            │
│  ┌─────────────────────────────┐   │
│  │  class ProductRepository    │   │
│  │    def published            │   │
│  │      model.published        │   │
│  │    end                      │   │
│  │  end                        │   │
│  └─────────────────────────────┘   │
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│        ActiveRecord Model           │
│  ┌─────────────────────────────┐   │
│  │  class Product < AppRecord  │   │
│  │    scope :published, ...    │   │
│  │  end                        │   │
│  └─────────────────────────────┘   │
└─────────────────────────────────────┘
```

---

## BaseRepository

### Creating a Repository

```ruby
# app/repositories/product_repository.rb
class ProductRepository < BetterService::Repository::BaseRepository
  def initialize(model_class = Product)
    super
  end
end
```

### Automatic Model Derivation

If your repository follows naming conventions, the model is derived automatically:

```ruby
# ProductRepository -> Product
class ProductRepository < BetterService::Repository::BaseRepository
end

# Bookings::BookingRepository -> Bookings::Booking
class Bookings::BookingRepository < BetterService::Repository::BaseRepository
end
```

### Standard CRUD Methods

BaseRepository provides all common operations:

```ruby
repo = ProductRepository.new

# Find
repo.find(1)                    # Find by ID (raises if not found)
repo.find_by(slug: "widget")    # Find by attributes (returns nil if not found)

# Query
repo.all                        # All records
repo.where(status: "active")    # ActiveRecord where
repo.count                      # Count records
repo.exists?(id: 1)            # Check existence

# Create
repo.build(name: "Widget")      # Build unsaved record
repo.create(name: "Widget")     # Create record (returns invalid if fails)
repo.create!(name: "Widget")    # Create record (raises if fails)

# Update
repo.update(product, name: "New Name")    # Update record (raises if fails)
repo.update(1, name: "New Name")          # Update by ID

# Delete
repo.destroy(product)           # Destroy with callbacks
repo.destroy(1)                 # Destroy by ID
repo.delete(product)            # Delete without callbacks
```

### Search Method

The powerful `search` method supports flexible querying:

```ruby
repo = ProductRepository.new

# Basic search
repo.search({ status_eq: "active" })

# With pagination
repo.search(
  { category_id_eq: 5 },
  page: 2,
  per_page: 25
)

# With eager loading
repo.search(
  { user_id_eq: 1 },
  includes: [:category, :images]
)

# With ordering
repo.search(
  {},
  order: "created_at DESC"
)

# Get single record
repo.search(
  { id_eq: 123 },
  limit: 1
)

# No pagination (get all)
repo.search(
  { status_eq: "active" },
  limit: nil
)

# Complex search
repo.search(
  {
    user_id_eq: user.id,
    status_in: ["pending", "confirmed"],
    created_at_gteq: 1.week.ago
  },
  includes: [:user, :comments],
  joins: [:category],
  order: "created_at DESC",
  per_page: 20
)
```

### Search Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `predicates` | Hash | `{}` | Search predicates (see below) |
| `page` | Integer | `1` | Page number |
| `per_page` | Integer | `20` | Records per page |
| `includes` | Array | `[]` | Associations to eager load |
| `joins` | Array | `[]` | Associations to join |
| `order` | String/Hash | `nil` | Order clause |
| `order_scope` | Hash | `nil` | Named scope `{ field:, direction: }` |
| `limit` | Integer/Symbol/nil | `:default` | Limit behavior |

### Limit Options

| Value | Behavior |
|-------|----------|
| `1` | Returns single record (`.first`) |
| `Integer > 1` | Limit to N records |
| `nil` | No limit (all records) |
| `:default` | Apply pagination |

---

## RepositoryAware Concern

### Basic Usage

Include the concern and declare repositories:

```ruby
class Products::IndexService < BetterService::IndexService
  include BetterService::Concerns::Serviceable::RepositoryAware

  repository :product

  search_with do
    { items: product_repository.all.to_a }
  end
end
```

### DSL Options

```ruby
# Default: derives class from name
repository :product
# => ProductRepository.new
# => Access via: product_repository

# Custom class name
repository :user, class_name: "Users::UserRepository"
# => Users::UserRepository.new
# => Access via: user_repository

# Custom accessor name
repository :booking, as: :bookings
# => BookingRepository.new
# => Access via: bookings (not booking_repository)
```

### Multiple Repositories

```ruby
class Orders::CreateService < BetterService::CreateService
  include BetterService::Concerns::Serviceable::RepositoryAware

  repository :order
  repository :product
  repository :inventory, class_name: "Warehouse::InventoryRepository"

  process_with do
    # Use all repositories
    product = product_repository.find(params[:product_id])
    inventory = inventory.check_stock(product)

    order = order_repository.create!(
      user: user,
      product: product,
      quantity: params[:quantity]
    )

    { resource: order }
  end
end
```

---

## Custom Repositories

### Domain-Specific Methods

```ruby
class ProductRepository < BetterService::Repository::BaseRepository
  def initialize
    super(Product)
  end

  # Simple scope delegation
  def published
    model.published
  end

  def featured
    model.featured
  end

  # Filtered queries
  def by_category(category_id)
    where(category_id: category_id)
  end

  def by_user(user)
    where(user_id: user.id)
  end

  # Complex queries
  def recent(limit = 10)
    model.order(created_at: :desc).limit(limit)
  end

  def best_sellers(limit = 10)
    model.joins(:order_items)
         .group(:id)
         .order("COUNT(order_items.id) DESC")
         .limit(limit)
  end

  def low_stock(threshold = 5)
    where("stock <= ?", threshold)
  end

  def search_by_name(query)
    where("name ILIKE ?", "%#{query}%")
  end

  # Aggregations
  def total_value
    model.sum("price * stock")
  end

  def average_price
    model.average(:price)
  end

  # Batch operations
  def mark_all_published(ids)
    model.where(id: ids).update_all(published: true, published_at: Time.current)
  end
end
```

### Using Custom Methods in Services

```ruby
class Products::IndexService < BetterService::IndexService
  include BetterService::Concerns::Serviceable::RepositoryAware

  repository :product

  search_with do
    products = case params[:filter]
               when "featured" then product_repository.featured
               when "recent" then product_repository.recent(20)
               when "low_stock" then product_repository.low_stock
               else product_repository.published
               end

    if params[:category_id]
      products = products.merge(
        product_repository.by_category(params[:category_id])
      )
    end

    { items: products.to_a }
  end
end
```

### Chaining Repository Methods

```ruby
class ProductRepository < BetterService::Repository::BaseRepository
  def published
    model.where(published: true)
  end

  def in_stock
    model.where("stock > 0")
  end

  def by_category(category_id)
    model.where(category_id: category_id)
  end

  # Chainable method that returns relation
  def available
    published.merge(in_stock)
  end
end

# Usage
product_repository.available.merge(
  product_repository.by_category(5)
).order(created_at: :desc)
```

---

## Predicates and Search

### Predicate Suffixes

If your model has a `search` scope (e.g., via Ransack or custom implementation), predicates are automatically applied:

| Suffix | Meaning | Example |
|--------|---------|---------|
| `_eq` | Equals | `status_eq: "active"` |
| `_not_eq` | Not equals | `status_not_eq: "deleted"` |
| `_in` | In array | `status_in: ["a", "b"]` |
| `_not_in` | Not in array | `status_not_in: ["x"]` |
| `_lt` | Less than | `price_lt: 100` |
| `_lteq` | Less than or equal | `price_lteq: 100` |
| `_gt` | Greater than | `price_gt: 50` |
| `_gteq` | Greater than or equal | `price_gteq: 50` |
| `_cont` | Contains | `name_cont: "widget"` |
| `_start` | Starts with | `name_start: "Pro"` |
| `_end` | Ends with | `name_end: "ium"` |

### Example with Predicates

```ruby
repo.search({
  # Exact match
  status_eq: "active",
  user_id_eq: current_user.id,

  # Range
  price_gteq: 10,
  price_lteq: 100,

  # Multiple values
  category_id_in: [1, 2, 3],

  # Date ranges
  created_at_gteq: 1.week.ago,
  created_at_lteq: Time.current,

  # Text search
  name_cont: params[:search]
})
```

### Implementing Searchable in Model

```ruby
# app/models/product.rb
class Product < ApplicationRecord
  scope :search, ->(predicates) {
    result = all

    predicates.each do |key, value|
      next if value.blank?

      field, operator = parse_predicate(key)

      result = case operator
               when "eq" then result.where(field => value)
               when "in" then result.where(field => value)
               when "lt" then result.where("#{field} < ?", value)
               when "lteq" then result.where("#{field} <= ?", value)
               when "gt" then result.where("#{field} > ?", value)
               when "gteq" then result.where("#{field} >= ?", value)
               when "cont" then result.where("#{field} ILIKE ?", "%#{value}%")
               else result
               end
    end

    result
  }

  private

  def self.parse_predicate(key)
    key.to_s.match(/^(.+)_(eq|in|lt|lteq|gt|gteq|cont)$/)&.captures || [key, "eq"]
  end
end
```

---

## Testing with Repositories

### Mocking Repositories

```ruby
class Products::IndexServiceTest < ActiveSupport::TestCase
  test "returns published products" do
    # Create mock repository
    mock_repo = Minitest::Mock.new
    mock_products = [
      Product.new(id: 1, name: "A"),
      Product.new(id: 2, name: "B")
    ]

    mock_repo.expect(:published, mock_products)

    # Inject mock
    service = Products::IndexService.new(user, params: {})
    service.instance_variable_set(:@product_repository, mock_repo)

    result = service.call

    assert_equal 2, result[:items].count
    mock_repo.verify
  end
end
```

### Testing Repository Directly

```ruby
class ProductRepositoryTest < ActiveSupport::TestCase
  setup do
    @repo = ProductRepository.new
    @user = users(:one)
  end

  test "published returns only published products" do
    published = products(:published)
    unpublished = products(:draft)

    result = @repo.published

    assert_includes result, published
    assert_not_includes result, unpublished
  end

  test "by_category filters by category" do
    electronics = categories(:electronics)
    product = products(:laptop)

    result = @repo.by_category(electronics.id)

    assert_includes result, product
  end

  test "search with predicates works" do
    result = @repo.search(
      { status_eq: "active", price_lteq: 100 },
      per_page: 10
    )

    assert result.all? { |p| p.status == "active" && p.price <= 100 }
    assert result.size <= 10
  end

  test "create! raises on invalid data" do
    assert_raises(ActiveRecord::RecordInvalid) do
      @repo.create!(name: nil)  # name is required
    end
  end
end
```

### Integration Tests

```ruby
class Products::CreateServiceIntegrationTest < ActiveSupport::TestCase
  test "creates product with repository" do
    user = users(:one)

    result = Products::CreateService.new(
      user,
      params: { name: "New Product", price: 99.99 }
    ).call

    assert result[:success]
    assert Product.exists?(name: "New Product")
  end
end
```

---

## Best Practices

### 1. Keep Repositories Focused

```ruby
# GOOD: Repository for one model
class ProductRepository < BetterService::Repository::BaseRepository
end

class CategoryRepository < BetterService::Repository::BaseRepository
end

# BAD: Repository for multiple models
class ShopRepository
  def find_product(id)
    Product.find(id)
  end

  def find_category(id)
    Category.find(id)
  end
end
```

### 2. Encapsulate Complex Queries

```ruby
# GOOD: Complex query in repository
class ProductRepository < BetterService::Repository::BaseRepository
  def trending(period: 7.days)
    model.joins(:order_items)
         .where(order_items: { created_at: period.ago.. })
         .group(:id)
         .order("COUNT(order_items.id) DESC")
         .limit(10)
  end
end

# BAD: Complex query in service
class Products::TrendingService < BetterService::IndexService
  search_with do
    items = Product.joins(:order_items)
                   .where(order_items: { created_at: 7.days.ago.. })
                   .group(:id)
                   .order("COUNT(order_items.id) DESC")
                   .limit(10)
    { items: items }
  end
end
```

### 3. Return Relations for Chaining

```ruby
# GOOD: Returns relation for chaining
def published
  model.where(published: true)  # Returns ActiveRecord::Relation
end

# Then you can chain:
product_repository.published.order(created_at: :desc).limit(10)

# BAD: Returns array (can't chain)
def published
  model.where(published: true).to_a  # Returns Array
end
```

### 4. Use Explicit Model Class When Needed

```ruby
# When naming doesn't match convention
class Bookings::ReservationRepository < BetterService::Repository::BaseRepository
  def initialize
    super(Booking)  # Model is Booking, not Bookings::Reservation
  end
end
```

### 5. Create Base Repository for Shared Logic

```ruby
# app/repositories/application_repository.rb
class ApplicationRepository < BetterService::Repository::BaseRepository
  def active
    model.where(deleted_at: nil)
  end

  def recent(limit = 10)
    model.order(created_at: :desc).limit(limit)
  end

  def by_user(user)
    model.where(user_id: user.id)
  end
end

# app/repositories/product_repository.rb
class ProductRepository < ApplicationRepository
  def initialize
    super(Product)
  end

  def published
    active.where(published: true)
  end
end
```

### 6. File Organization

```
app/
├── repositories/
│   ├── application_repository.rb   # Shared base
│   ├── product_repository.rb
│   ├── user_repository.rb
│   └── orders/
│       ├── order_repository.rb
│       └── line_item_repository.rb
├── services/
│   └── products/
│       ├── index_service.rb
│       └── create_service.rb
└── models/
    ├── product.rb
    └── user.rb
```

---

## See Also

- **Micro-examples**: `/context7/repository/` - Quick patterns and examples
- **RepositoryAware Concern**: Integration with services
- **Testing Guide**: `/docs/testing.md` - Testing strategies
