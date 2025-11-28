# Custom Repository Examples

## Basic Custom Repository

```ruby
class ProductRepository < BetterService::Repository::BaseRepository
  def initialize
    super(Product)
  end

  # Delegate to model scope
  def published
    model.published
  end

  def unpublished
    model.unpublished
  end

  # Custom query
  def by_user(user_id)
    where(user_id: user_id)
  end
end
```

## Query Method Patterns

### Delegating to Model Scopes

When your model already has scopes, delegate to them:

```ruby
# Model
class Product < ApplicationRecord
  scope :published, -> { where(published: true) }
  scope :featured, -> { where(featured: true) }
  scope :in_stock, -> { where("quantity > 0") }
end

# Repository
class ProductRepository < BetterService::Repository::BaseRepository
  def initialize
    super(Product)
  end

  def published
    model.published
  end

  def featured
    model.featured
  end

  def in_stock
    model.in_stock
  end

  # Combine scopes
  def featured_in_stock
    model.featured.in_stock
  end
end
```

### Using Where Conditions

Build custom queries with `where`:

```ruby
class ProductRepository < BetterService::Repository::BaseRepository
  def initialize
    super(Product)
  end

  # Simple where
  def by_category(category_id)
    where(category_id: category_id)
  end

  # Range condition
  def in_price_range(min, max)
    where(price: min..max)
  end

  # Array condition
  def by_ids(ids)
    where(id: ids)
  end

  # Date condition
  def created_after(date)
    where("created_at > ?", date)
  end

  # Null check
  def without_category
    where(category_id: nil)
  end
end
```

### Eager Loading Associations

```ruby
class UserRepository < BetterService::Repository::BaseRepository
  def initialize
    super(User)
  end

  def with_products
    model.includes(:products)
  end

  def with_bookings
    model.includes(:bookings)
  end

  def with_all_associations
    model.includes(:products, :bookings, :orders)
  end

  # Nested eager loading
  def with_products_and_categories
    model.includes(products: :category)
  end
end
```

### Semantic Query Methods

Give business meaning to queries:

```ruby
class BookingRepository < BetterService::Repository::BaseRepository
  def initialize
    super(Booking)
  end

  # Time-based queries
  def upcoming
    where("date >= ?", Date.current)
  end

  def past
    where("date < ?", Date.current)
  end

  def today
    where(date: Date.current)
  end

  def this_week
    where(date: Date.current.beginning_of_week..Date.current.end_of_week)
  end

  def this_month
    where(date: Date.current.beginning_of_month..Date.current.end_of_month)
  end

  # Specific date
  def for_date(date)
    where(date: date)
  end

  # Date range
  def between(start_date, end_date)
    where(date: start_date..end_date)
  end
end
```

### Finder Methods

```ruby
class UserRepository < BetterService::Repository::BaseRepository
  def initialize
    super(User)
  end

  def find_by_email(email)
    find_by(email: email)
  end

  def find_by_token(token)
    find_by(auth_token: token)
  end

  def find_active_by_email(email)
    find_by(email: email, active: true)
  end
end
```

## Complete Repository Examples

### ProductRepository

```ruby
class ProductRepository < BetterService::Repository::BaseRepository
  def initialize
    super(Product)
  end

  # Scopes
  def published
    model.published
  end

  def unpublished
    model.unpublished
  end

  def featured
    model.featured
  end

  # Filters
  def by_user(user_id)
    where(user_id: user_id)
  end

  def by_category(category_id)
    where(category_id: category_id)
  end

  def in_price_range(min_price, max_price)
    where(price: min_price..max_price)
  end

  # Ordering
  def newest_first
    model.order(created_at: :desc)
  end

  def cheapest_first
    model.order(price: :asc)
  end

  def most_expensive_first
    model.order(price: :desc)
  end

  # Combined queries
  def published_by_category(category_id)
    published.where(category_id: category_id)
  end

  def featured_under_price(max_price)
    featured.where("price <= ?", max_price)
  end

  # Aggregations
  def average_price
    model.average(:price)
  end

  def total_value
    model.sum(:price)
  end

  # Search
  def search_by_name(query)
    where("name ILIKE ?", "%#{query}%")
  end
end
```

### OrderRepository

```ruby
class OrderRepository < BetterService::Repository::BaseRepository
  def initialize
    super(Order)
  end

  # Status filters
  def pending
    where(status: "pending")
  end

  def processing
    where(status: "processing")
  end

  def completed
    where(status: "completed")
  end

  def cancelled
    where(status: "cancelled")
  end

  # User filters
  def by_user(user_id)
    where(user_id: user_id)
  end

  def by_customer(customer_id)
    where(customer_id: customer_id)
  end

  # Date filters
  def placed_today
    where(created_at: Date.current.all_day)
  end

  def placed_this_week
    where(created_at: 1.week.ago..Time.current)
  end

  def placed_this_month
    where(created_at: 1.month.ago..Time.current)
  end

  def in_date_range(start_date, end_date)
    where(created_at: start_date.beginning_of_day..end_date.end_of_day)
  end

  # Combined
  def pending_by_user(user_id)
    pending.where(user_id: user_id)
  end

  def completed_in_range(start_date, end_date)
    completed.in_date_range(start_date, end_date)
  end

  # Eager loading
  def with_items
    model.includes(:order_items)
  end

  def with_customer
    model.includes(:customer)
  end

  def with_all
    model.includes(:order_items, :customer, :payments)
  end

  # Aggregations
  def total_revenue
    completed.sum(:total)
  end

  def average_order_value
    completed.average(:total)
  end

  def orders_count_by_status
    model.group(:status).count
  end
end
```

### BookingRepository

```ruby
class BookingRepository < BetterService::Repository::BaseRepository
  def initialize
    super(Booking)
  end

  # Time-based
  def upcoming
    where("date >= ?", Date.current).order(:date)
  end

  def past
    where("date < ?", Date.current).order(date: :desc)
  end

  def today
    where(date: Date.current)
  end

  def for_date(date)
    where(date: date)
  end

  def between_dates(start_date, end_date)
    where(date: start_date..end_date)
  end

  # User filters
  def by_user(user_id)
    where(user_id: user_id)
  end

  def upcoming_for_user(user_id)
    upcoming.where(user_id: user_id)
  end

  # Status
  def confirmed
    where(status: "confirmed")
  end

  def pending_confirmation
    where(status: "pending")
  end

  def cancelled
    where(status: "cancelled")
  end

  # Availability check
  def conflicting(date, start_time, end_time)
    where(date: date)
      .where("start_time < ? AND end_time > ?", end_time, start_time)
  end

  def available_slots_on(date)
    # Returns time slots not taken
    taken = for_date(date).pluck(:start_time, :end_time)
    # ... calculate available slots
  end

  # Eager loading
  def with_user
    model.includes(:user)
  end

  def with_resource
    model.includes(:bookable_resource)
  end
end
```

## Chainable Methods

All repository methods returning relations are chainable:

```ruby
repo = ProductRepository.new

# Chain multiple methods
products = repo.published
               .by_category(5)
               .in_price_range(10, 100)
               .newest_first
               .limit(10)

# Chain with ActiveRecord methods
products = repo.published
               .includes(:reviews)
               .order(rating: :desc)
               .page(1)
               .per(20)

# Count after chaining
count = repo.published.by_category(5).count

# Check existence after chaining
exists = repo.published.by_user(user.id).exists?
```

## Pattern: Application Repository

Create a base repository for your app:

```ruby
# app/repositories/application_repository.rb
class ApplicationRepository < BetterService::Repository::BaseRepository
  # Shared methods for all repositories

  def active
    where(active: true)
  end

  def inactive
    where(active: false)
  end

  def recent(limit = 10)
    model.order(created_at: :desc).limit(limit)
  end

  def by_ids(ids)
    where(id: ids)
  end
end

# app/repositories/product_repository.rb
class ProductRepository < ApplicationRepository
  def initialize
    super(Product)
  end

  # Product-specific methods
  def published
    active.where(published: true)
  end
end
```

## Anti-Patterns to Avoid

### Don't Put Business Logic in Repository

```ruby
# Bad - business logic in repository
class OrderRepository < BetterService::Repository::BaseRepository
  def create_with_discount(attrs, discount_code)
    discount = Discount.find_by(code: discount_code)
    attrs[:total] = attrs[:total] * (1 - discount.percentage)
    create!(attrs)
  end
end

# Good - repository just handles data access
class OrderRepository < BetterService::Repository::BaseRepository
  # Simple CRUD only
end

# Business logic in service
class Orders::CreateService < BetterService::Services::CreateService
  include BetterService::Concerns::Serviceable::RepositoryAware
  repository :order

  process_with do |data|
    discount = calculate_discount(params[:discount_code])
    total = data[:subtotal] * (1 - discount)
    { resource: order_repository.create!(total: total, **params) }
  end
end
```

### Don't Expose Model Directly

```ruby
# Bad - leaking model class
class ProductRepository < BetterService::Repository::BaseRepository
  def get_model
    model  # Don't expose this
  end
end

# Good - provide specific query methods
class ProductRepository < BetterService::Repository::BaseRepository
  def table_name
    model.table_name
  end

  def column_names
    model.column_names
  end
end
```
