# Repositories

Learn the Repository pattern for data access.

---

## Why Repositories?

### Benefits of the Pattern

Repositories provide a clean abstraction over data access.

```ruby
# Without repository: direct ActiveRecord in services
class Product::IndexService < BetterService::Services::Base
  search_with do
    products = Product.where(published: true)
                      .where("price > ?", 0)
                      .order(created_at: :desc)
    { items: products }
  end
end

# With repository: encapsulated queries
class Product::IndexService < Product::BaseService
  search_with do
    { items: product_repository.published.available.recent }
  end
end
```

--------------------------------

## Creating a Repository

### Basic Repository

Generate and customize a repository.

```bash
# Generate with base generator
rails g serviceable:base Product
# Creates: app/repositories/product_repository.rb
```

```ruby
# app/repositories/product_repository.rb
class ProductRepository < BetterService::Repositories::Base
  model Product
end
```

--------------------------------

### Define the Model

The model declaration links the repository to ActiveRecord.

```ruby
class ProductRepository < BetterService::Repositories::Base
  model Product  # Links to Product model

  # scope is now available as Product.all
end
```

--------------------------------

## Built-in Methods

### CRUD Operations

Repositories provide standard CRUD methods.

```ruby
repository = ProductRepository.new

# Find by ID
product = repository.find(1)
product = repository.find_by(slug: "widget")

# Create
product = repository.create!(name: "Widget", price: 99.99)

# Update
repository.update!(product, price: 149.99)

# Destroy
repository.destroy!(product)

# Check existence
repository.exists?(id: 1)  # => true/false
```

--------------------------------

### Query Methods

Access the underlying scope.

```ruby
repository = ProductRepository.new

# Access all records
repository.all         # => ActiveRecord::Relation
repository.scope       # => Same as all

# Count
repository.count       # => Integer

# First/Last
repository.first       # => Product or nil
repository.last        # => Product or nil
```

--------------------------------

## Custom Queries

### Scope Methods

Define custom query methods.

```ruby
class ProductRepository < BetterService::Repositories::Base
  model Product

  def published
    scope.where(published: true)
  end

  def by_category(category)
    scope.where(category: category)
  end

  def price_range(min, max)
    scope.where(price: min..max)
  end

  def recent(limit = 10)
    scope.order(created_at: :desc).limit(limit)
  end

  def search(query)
    scope.where("name ILIKE ?", "%#{query}%")
  end
end
```

--------------------------------

### Chainable Queries

Methods can be chained together.

```ruby
repository = ProductRepository.new

# Chain multiple scopes
products = repository.published
                     .by_category("electronics")
                     .price_range(100, 500)
                     .recent(20)

# Convert to array
products.to_a
```

--------------------------------

### Complex Queries

Handle complex query logic.

```ruby
class ProductRepository < BetterService::Repositories::Base
  model Product

  def featured
    scope.where(featured: true)
         .where("stock > 0")
         .order(sales_count: :desc)
  end

  def with_reviews
    scope.joins(:reviews)
         .group("products.id")
         .having("COUNT(reviews.id) > 0")
  end

  def best_sellers(period: 30.days)
    scope.joins(:order_items)
         .where("order_items.created_at > ?", period.ago)
         .group("products.id")
         .order("SUM(order_items.quantity) DESC")
  end

  def low_stock(threshold: 10)
    scope.where("stock <= ?", threshold)
  end
end
```

--------------------------------

## Using in Services

### RepositoryAware Concern

Include the concern to get repository access.

```ruby
class Product::BaseService < BetterService::Services::Base
  include BetterService::Concerns::Serviceable::RepositoryAware

  repository :product  # Adds product_repository method
end

class Product::IndexService < Product::BaseService
  search_with do
    # product_repository is available
    { items: product_repository.published.to_a }
  end
end
```

--------------------------------

### Multiple Repositories

Access multiple repositories in a service.

```ruby
class Order::CreateService < Order::BaseService
  include BetterService::Concerns::Serviceable::RepositoryAware

  repository :order
  repository :product
  repository :user

  process_with do |data|
    product = product_repository.find(params[:product_id])
    buyer = user_repository.find(params[:user_id])

    order = order_repository.create!(
      product: product,
      user: buyer,
      quantity: params[:quantity]
    )

    { resource: order }
  end
end
```

--------------------------------

## Predicates

### Built-in Predicates

Repositories generate predicate methods automatically.

```ruby
class ProductRepository < BetterService::Repositories::Base
  model Product

  def published
    scope.where(published: true)
  end

  def active
    scope.where(active: true)
  end
end

repository = ProductRepository.new

# Predicate methods check if ANY records match
repository.published?  # => true if any published products
repository.active?     # => true if any active products

# With additional conditions
repository.published.where(category: "books").any?
```

--------------------------------

## Pagination

### Paginated Queries

Handle pagination in repositories.

```ruby
class ProductRepository < BetterService::Repositories::Base
  model Product

  def paginate(page:, per_page: 25)
    scope.page(page).per(per_page)
  end

  def search(query, page: 1, per_page: 25)
    scope.where("name ILIKE ?", "%#{query}%")
         .page(page)
         .per(per_page)
  end
end

# In service
search_with do
  result = product_repository.search(
    params[:query],
    page: params[:page] || 1,
    per_page: params[:per_page] || 25
  )

  {
    items: result.to_a,
    total: result.total_count,
    page: result.current_page,
    total_pages: result.total_pages
  }
end
```

--------------------------------

## Associations

### Eager Loading

Optimize queries with includes.

```ruby
class ProductRepository < BetterService::Repositories::Base
  model Product

  def with_associations
    scope.includes(:category, :reviews, :images)
  end

  def with_seller
    scope.includes(:user)
  end

  def detailed
    scope.includes(:category, :reviews, :images, user: :profile)
  end
end

# In service - prevents N+1 queries
search_with do
  { items: product_repository.detailed.published.to_a }
end
```

--------------------------------

### Joins for Filtering

Use joins when you need to filter by association.

```ruby
class ProductRepository < BetterService::Repositories::Base
  model Product

  def by_seller_name(name)
    scope.joins(:user).where(users: { name: name })
  end

  def highly_rated(min_rating: 4.0)
    scope.joins(:reviews)
         .group("products.id")
         .having("AVG(reviews.rating) >= ?", min_rating)
  end

  def in_category(category_name)
    scope.joins(:category).where(categories: { name: category_name })
  end
end
```

--------------------------------

## Error Handling

### Handle Not Found

Wrap ActiveRecord exceptions.

```ruby
class ProductRepository < BetterService::Repositories::Base
  model Product

  def find_or_fail(id)
    find(id)
  rescue ActiveRecord::RecordNotFound
    raise BetterService::Errors::Runtime::ResourceNotFoundError.new(
      "Product not found",
      context: { id: id, model: "Product" }
    )
  end
end

# In service
search_with do
  { resource: product_repository.find_or_fail(params[:id]) }
end
```

--------------------------------

## Testing Repositories

### Repository Tests

Test your custom query methods.

```ruby
class ProductRepositoryTest < ActiveSupport::TestCase
  setup do
    @repository = ProductRepository.new
    @published = Product.create!(name: "Pub", price: 10, published: true)
    @draft = Product.create!(name: "Draft", price: 20, published: false)
  end

  test "published returns only published products" do
    result = @repository.published

    assert_includes result, @published
    refute_includes result, @draft
  end

  test "price_range filters correctly" do
    cheap = Product.create!(name: "Cheap", price: 5, published: true)
    expensive = Product.create!(name: "Expensive", price: 100, published: true)

    result = @repository.price_range(1, 15)

    assert_includes result, cheap
    assert_includes result, @published
    refute_includes result, expensive
  end

  test "chaining works" do
    result = @repository.published.price_range(5, 50)

    assert_includes result, @published
    refute_includes result, @draft
  end
end
```

--------------------------------

## Best Practices

### Repository Guidelines

Follow these patterns for clean repositories.

```ruby
# 1. Keep queries in repositories, not services
# Bad: query in service
search_with do
  { items: Product.where(published: true).where("price > 0") }
end

# Good: query in repository
search_with do
  { items: product_repository.published.available }
end

# 2. Name methods descriptively
def recent_bestsellers(limit: 10)
  # Clear what this returns
end

# 3. Return relations, not arrays
# Good: allows chaining
def published
  scope.where(published: true)
end

# Bad: breaks chaining
def published
  scope.where(published: true).to_a
end

# 4. Handle errors appropriately
def find_or_fail(id)
  find(id)
rescue ActiveRecord::RecordNotFound
  raise ResourceNotFoundError.new("...")
end
```

--------------------------------

## Next Steps

### Continue Learning

What to learn next.

```ruby
# Now that you understand repositories:

# 1. Build workflows
#    → guide/06-workflows.md

# 2. Handle errors
#    → guide/07-error-handling.md
```

--------------------------------
