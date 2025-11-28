# BaseRepository Methods

## Initialization

```ruby
class ProductRepository < BetterService::Repository::BaseRepository
  def initialize
    super(Product)  # Pass the model class
  end
end

# Or with auto-derivation (ProductRepository -> Product)
class ProductRepository < BetterService::Repository::BaseRepository
  # Model class derived from repository name
end
```

## Query Methods (Delegated from ActiveRecord)

### find(id)

Find a record by primary key. Raises `ActiveRecord::RecordNotFound` if not found.

```ruby
repo = ProductRepository.new

# Find by ID
product = repo.find(1)
# => #<Product id: 1, name: "Widget">

# Raises if not found
repo.find(999)
# => ActiveRecord::RecordNotFound: Couldn't find Product with 'id'=999
```

### find_by(conditions)

Find first record matching conditions. Returns `nil` if not found.

```ruby
repo = ProductRepository.new

# Find by single condition
product = repo.find_by(name: "Widget")
# => #<Product id: 1, name: "Widget">

# Find by multiple conditions
product = repo.find_by(name: "Widget", published: true)
# => #<Product id: 1, name: "Widget", published: true>

# Returns nil if not found
repo.find_by(name: "Nonexistent")
# => nil
```

### where(conditions)

Filter records by conditions. Returns an ActiveRecord relation.

```ruby
repo = ProductRepository.new

# Simple condition
products = repo.where(published: true)
# => #<ActiveRecord::Relation [...]>

# Multiple conditions
products = repo.where(published: true, category_id: 5)

# Range condition
products = repo.where(price: 10..50)

# Array condition
products = repo.where(id: [1, 2, 3])

# SQL string (use with caution)
products = repo.where("price > ?", 100)

# Chainable
products = repo.where(published: true).where(featured: true)
```

### all

Returns all records as an ActiveRecord relation.

```ruby
repo = ProductRepository.new

products = repo.all
# => #<ActiveRecord::Relation [...]>

# Chainable
products = repo.all.order(:name).limit(10)
```

### count

Returns the count of records.

```ruby
repo = ProductRepository.new

# Total count
repo.count
# => 42

# Count is available on filtered results too
repo.where(published: true).count
# => 35
```

### exists?(conditions)

Check if any record matches the conditions.

```ruby
repo = ProductRepository.new

# Check by conditions
repo.exists?(name: "Widget")
# => true

# Check by ID
repo.exists?(1)
# => true

# Check any existence
repo.exists?
# => true (if any records exist)
```

## Record Building

### build(attributes) / new(attributes)

Create an unsaved instance of the model.

```ruby
repo = ProductRepository.new

# Build new record (not saved)
product = repo.build(name: "New Widget", price: 29.99)
# => #<Product id: nil, name: "New Widget", price: 29.99>

product.persisted?
# => false

# Alias
product = repo.new(name: "Another Widget")
```

## CRUD Operations

### create(attributes)

Create a new record. Returns the record (may be invalid).

```ruby
repo = ProductRepository.new

# Create valid record
product = repo.create(name: "Widget", price: 29.99)
# => #<Product id: 1, name: "Widget">

product.persisted?
# => true

# Create with validation errors (returns invalid record)
product = repo.create(name: nil)  # if name is required
product.persisted?
# => false
product.errors.full_messages
# => ["Name can't be blank"]
```

### create!(attributes)

Create a new record with validation. Raises on failure.

```ruby
repo = ProductRepository.new

# Create valid record
product = repo.create!(name: "Widget", price: 29.99)
# => #<Product id: 1, name: "Widget">

# Raises on validation failure
repo.create!(name: nil)
# => ActiveRecord::RecordInvalid: Validation failed: Name can't be blank
```

### update(record_or_id, attributes)

Update an existing record. Raises on validation failure.

```ruby
repo = ProductRepository.new

# Update by record instance
product = repo.find(1)
repo.update(product, name: "Updated Widget", price: 39.99)
# => #<Product id: 1, name: "Updated Widget", price: 39.99>

# Update by ID
repo.update(1, name: "Another Update")
# => #<Product id: 1, name: "Another Update">

# Raises on validation failure
repo.update(product, name: nil)
# => ActiveRecord::RecordInvalid
```

### destroy(record_or_id)

Delete a record with callbacks (before_destroy, after_destroy).

```ruby
repo = ProductRepository.new

# Destroy by record
product = repo.find(1)
repo.destroy(product)
# => #<Product id: 1, ...> (frozen)

Product.exists?(1)
# => false

# Destroy by ID
repo.destroy(2)
```

### delete(record_or_id)

Delete a record WITHOUT callbacks. Use with caution.

```ruby
repo = ProductRepository.new

# Delete by ID (skips callbacks)
repo.delete(1)

# Delete by record
product = repo.find(2)
repo.delete(product)
```

## Advanced Search

### search(predicates, options)

Powerful search with pagination, eager loading, and ordering.

```ruby
repo = ProductRepository.new
```

#### Basic Search with Pagination

```ruby
# Default pagination (page 1, 20 per page)
results = repo.search({})
# => ActiveRecord::Relation with first 20 records

# Custom pagination
results = repo.search({}, page: 2, per_page: 10)
# => Records 11-20
```

#### Search with Predicates

Predicates follow Ransack-style naming:

```ruby
# Equality
results = repo.search({ status_eq: "active" })

# Greater than / Less than
results = repo.search({ price_gt: 100 })
results = repo.search({ price_lt: 50 })
results = repo.search({ price_gteq: 100 })  # >=
results = repo.search({ price_lteq: 50 })   # <=

# Contains (LIKE)
results = repo.search({ name_cont: "widget" })
# => WHERE name LIKE '%widget%'

# Starts with / Ends with
results = repo.search({ name_start: "Pro" })
results = repo.search({ name_end: "Widget" })

# In array
results = repo.search({ status_in: ["active", "pending"] })

# Null checks
results = repo.search({ deleted_at_null: true })
results = repo.search({ deleted_at_not_null: true })

# Multiple predicates (AND)
results = repo.search({
  status_eq: "active",
  price_gteq: 100,
  name_cont: "premium"
})
```

#### Eager Loading

```ruby
# Single association
results = repo.search({}, includes: [:category])

# Multiple associations
results = repo.search({}, includes: [:category, :reviews, :images])

# Nested associations
results = repo.search({}, includes: [{ category: :parent }, :reviews])
```

#### Joins

```ruby
# Join for filtering
results = repo.search(
  { category_name_eq: "Electronics" },
  joins: [:category]
)
```

#### Ordering

```ruby
# Simple order
results = repo.search({}, order: { created_at: :desc })

# Multiple order clauses
results = repo.search({}, order: { featured: :desc, name: :asc })

# Order by scope
results = repo.search({}, order_scope: { field: :price, direction: :asc })
```

#### Limit Control

```ruby
# Get single record
result = repo.search({ status_eq: "active" }, limit: 1)
# => Single record (not relation)

# Custom limit
results = repo.search({}, limit: 5)
# => First 5 records

# No limit (all records)
results = repo.search({}, limit: nil)
# => All matching records

# Default pagination
results = repo.search({}, limit: :default)
# => Paginated results (default behavior)
```

#### Complete Example

```ruby
results = repo.search(
  {
    published_eq: true,
    price_gteq: 50,
    name_cont: "premium"
  },
  page: 1,
  per_page: 20,
  includes: [:category, :reviews],
  order: { created_at: :desc }
)
```

## Method Summary

| Method | Returns | Raises | Purpose |
|--------|---------|--------|---------|
| `find(id)` | Record | `RecordNotFound` | Find by primary key |
| `find_by(conditions)` | Record or nil | - | Find first match |
| `where(conditions)` | Relation | - | Filter records |
| `all` | Relation | - | All records |
| `count` | Integer | - | Record count |
| `exists?(conditions)` | Boolean | - | Check existence |
| `build(attrs)` | Unsaved record | - | Create instance |
| `create(attrs)` | Record | - | Create (may be invalid) |
| `create!(attrs)` | Record | `RecordInvalid` | Create with validation |
| `update(record, attrs)` | Record | `RecordInvalid` | Update record |
| `destroy(record)` | Frozen record | - | Delete with callbacks |
| `delete(record)` | - | - | Delete without callbacks |
| `search(predicates, opts)` | Relation | - | Advanced search |
