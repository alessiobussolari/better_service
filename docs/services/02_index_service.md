# IndexService

## Overview

IndexService is designed for retrieving collections of resources. It's optimized for listing, searching, filtering, and paginating data with automatic caching support.

**Characteristics:**
- **Action**: `:index`
- **Transaction**: Disabled (read-only operation)
- **Return Key**: `items` (array)
- **Default Schema**: Pagination and search parameters
- **Common Use Cases**: Lists, search results, filtered collections

## Generation

### Basic Generation

```bash
rails g serviceable:index Product
```

This generates:

```ruby
# app/services/product/index_service.rb
module Product
  class IndexService < BetterService::IndexService
    model_class Product

    schema do
      optional(:page).filled(:integer, gteq?: 1)
      optional(:per_page).filled(:integer, gteq?: 1, lteq?: 100)
      optional(:search).maybe(:string)
    end

    search_with do
      { items: model_class.all }
    end
  end
end
```

### Generation with Options

```bash
# With cache enabled
rails g serviceable:index Product --cache

# With presenter
rails g serviceable:index Product --presenter=ProductPresenter

# With specific namespace
rails g serviceable:index Admin::Product
```

## Schema

### Default Schema

IndexService comes with optional pagination parameters:

```ruby
schema do
  optional(:page).filled(:integer, gteq?: 1)
  optional(:per_page).filled(:integer, gteq?: 1, lteq?: 100)
  optional(:search).maybe(:string)
end
```

### Customizing Schema

Add your own filters and parameters:

```ruby
schema do
  # Pagination (optional)
  optional(:page).filled(:integer, gteq?: 1)
  optional(:per_page).filled(:integer, gteq?: 1, lteq?: 100)

  # Search
  optional(:search).maybe(:string)

  # Custom filters
  optional(:status).maybe(:string, included_in?: %w[active inactive pending])
  optional(:category_id).maybe(:integer)
  optional(:min_price).maybe(:decimal)
  optional(:max_price).maybe(:decimal)

  # Sorting
  optional(:sort_by).maybe(:string, included_in?: %w[name price created_at])
  optional(:sort_direction).maybe(:string, included_in?: %w[asc desc])

  # Date range
  optional(:start_date).maybe(:date)
  optional(:end_date).maybe(:date)
end
```

## Available Methods

### search_with

Loads the collection from database or external sources.

**Returns**: Hash with `:items` key containing an array.

```ruby
# Simple query
search_with do
  { items: Product.all }
end

# With filtering
search_with do
  scope = model_class.all

  scope = scope.where(status: params[:status]) if params[:status]
  scope = scope.where(category_id: params[:category_id]) if params[:category_id]
  scope = scope.where('name ILIKE ?', "%#{params[:search]}%") if params[:search]

  { items: scope }
end

# With eager loading
search_with do
  { items: Product.includes(:category, :reviews).all }
end

# With scopes
search_with do
  scope = Product.active
  scope = scope.recent if params[:recent]
  scope = scope.featured if params[:featured]

  { items: scope }
end
```

### process_with

Transforms or enriches the collection data.

**Input**: Hash from search (`:items` key)
**Returns**: Hash with `:items` key and optional metadata

```ruby
# Add metadata
process_with do |data|
  {
    items: data[:items],
    metadata: {
      total: data[:items].count,
      page: params[:page] || 1,
      per_page: params[:per_page] || 20
    }
  }
end

# Apply sorting
process_with do |data|
  items = data[:items]

  if params[:sort_by]
    direction = params[:sort_direction] || 'asc'
    items = items.order("#{params[:sort_by]} #{direction}")
  end

  { items: items }
end

# Aggregate calculations
process_with do |data|
  items = data[:items]

  {
    items: items,
    metadata: {
      total_count: items.count,
      total_value: items.sum(:price),
      average_price: items.average(:price)
    }
  }
end
```

### respond_with

Customizes the final response format.

**Input**: Hash from process/transform
**Returns**: Hash with `:success`, `:message`, and data

```ruby
# Custom message
respond_with do |data|
  count = data[:items].size
  success_result("Found #{count} products", data)
end

# Add custom keys
respond_with do |data|
  success_result("Products loaded", data).merge(
    filters_applied: params.slice(:status, :category_id),
    timestamp: Time.current
  )
end
```

## Configurations

### Cache Configuration

Enable automatic caching for read operations:

```ruby
class Product::IndexService < BetterService::IndexService
  model_class Product

  # Enable cache with contexts
  cache_contexts :products, :filters

  # Cache expires when products are created/updated/deleted
  # or when filters change

  schema do
    optional(:category_id).maybe(:integer)
    optional(:status).maybe(:string)
  end

  search_with do
    scope = model_class.all
    scope = scope.where(category_id: params[:category_id]) if params[:category_id]
    scope = scope.where(status: params[:status]) if params[:status]

    { items: scope }
  end
end
```

### Presenter Configuration

Apply presenters to format the output:

```ruby
class Product::IndexService < BetterService::IndexService
  model_class Product
  presenter ProductPresenter

  # Each item will be formatted by ProductPresenter

  search_with do
    { items: model_class.includes(:category, :reviews).all }
  end
end
```

Example presenter:

```ruby
class ProductPresenter
  def self.present(product)
    {
      id: product.id,
      name: product.name,
      price: product.price.to_f,
      category: product.category.name,
      rating: product.reviews.average(:rating)&.round(1)
    }
  end
end
```

### Authorization Configuration

Restrict access to the collection:

```ruby
class Product::IndexService < BetterService::IndexService
  model_class Product

  authorize_with do
    user.active? && user.has_permission?(:view_products)
  end

  search_with do
    # Only authorized users reach here
    { items: model_class.all }
  end
end
```

### Scope by User

Filter collection based on current user:

```ruby
class Order::IndexService < BetterService::IndexService
  model_class Order

  search_with do
    # Admins see all orders, users see only their own
    scope = user.admin? ? model_class.all : user.orders

    scope = scope.where(status: params[:status]) if params[:status]

    { items: scope }
  end
end
```

## Complete Examples

### Example 1: Basic Product Listing

```ruby
module Product
  class IndexService < BetterService::IndexService
    model_class Product

    schema do
      optional(:page).filled(:integer, gteq?: 1)
      optional(:per_page).filled(:integer, gteq?: 1, lteq?: 100)
    end

    search_with do
      { items: model_class.active.order(created_at: :desc) }
    end
  end
end

# Usage
result = Product::IndexService.new(current_user, params: { page: 1, per_page: 20 }).call
products = result[:items]
```

### Example 2: Advanced Search with Filters

```ruby
module Product
  class SearchService < BetterService::IndexService
    model_class Product
    cache_contexts :products, :search
    presenter ProductPresenter

    schema do
      optional(:search).maybe(:string)
      optional(:category_id).maybe(:integer)
      optional(:min_price).maybe(:decimal)
      optional(:max_price).maybe(:decimal)
      optional(:status).maybe(:string, included_in?: %w[active inactive])
      optional(:sort_by).maybe(:string, included_in?: %w[name price created_at])
      optional(:sort_direction).maybe(:string, included_in?: %w[asc desc])
    end

    search_with do
      scope = model_class.all

      # Text search
      if params[:search].present?
        scope = scope.where('name ILIKE ? OR description ILIKE ?',
                           "%#{params[:search]}%",
                           "%#{params[:search]}%")
      end

      # Filters
      scope = scope.where(category_id: params[:category_id]) if params[:category_id]
      scope = scope.where(status: params[:status]) if params[:status]
      scope = scope.where('price >= ?', params[:min_price]) if params[:min_price]
      scope = scope.where('price <= ?', params[:max_price]) if params[:max_price]

      { items: scope.includes(:category, :reviews) }
    end

    process_with do |data|
      items = data[:items]

      # Apply sorting
      if params[:sort_by]
        direction = params[:sort_direction] || 'asc'
        items = items.order("#{params[:sort_by]} #{direction}")
      end

      {
        items: items,
        metadata: {
          total: items.count,
          filters_applied: params.slice(:category_id, :status, :min_price, :max_price).compact
        }
      }
    end
  end
end

# Usage
result = Product::SearchService.new(current_user, params: {
  search: "laptop",
  category_id: 5,
  min_price: 500,
  sort_by: "price",
  sort_direction: "asc"
}).call

# => {
#   success: true,
#   message: "Products loaded successfully",
#   items: [...],
#   metadata: {
#     action: :index,
#     total: 42,
#     filters_applied: { category_id: 5, min_price: 500 }
#   }
# }
```

### Example 3: User-Scoped with Pagination

```ruby
module Order
  class MyOrdersService < BetterService::IndexService
    model_class Order
    cache_contexts :user_orders
    presenter OrderPresenter

    schema do
      optional(:page).filled(:integer, gteq?: 1)
      optional(:per_page).filled(:integer, gteq?: 1, lteq?: 50)
      optional(:status).maybe(:string, included_in?: %w[pending confirmed shipped delivered cancelled])
    end

    search_with do
      scope = user.orders.includes(:items, :shipping_address)
      scope = scope.where(status: params[:status]) if params[:status]

      { items: scope.order(created_at: :desc) }
    end

    process_with do |data|
      page = params[:page] || 1
      per_page = params[:per_page] || 20

      items = data[:items].page(page).per(per_page)

      {
        items: items,
        metadata: {
          page: page,
          per_page: per_page,
          total: items.total_count,
          total_pages: items.total_pages
        }
      }
    end
  end
end

# Usage
result = Order::MyOrdersService.new(current_user, params: {
  status: "confirmed",
  page: 2,
  per_page: 10
}).call

orders = result[:items]
pagination = result[:metadata]
```

### Example 4: External API Integration

```ruby
module Github
  class RepositoriesService < BetterService::IndexService
    self._allow_nil_user = true
    cache_contexts :github_repos

    schema do
      required(:username).filled(:string)
      optional(:type).maybe(:string, included_in?: %w[all owner member])
    end

    search_with do
      type = params[:type] || 'owner'
      response = Octokit.repos(params[:username], type: type)

      { items: response }
    rescue Octokit::Error => e
      raise BetterService::Errors::Runtime::ExecutionError.new(
        "Failed to fetch repositories: #{e.message}"
      )
    end

    process_with do |data|
      # Transform GitHub API response
      repos = data[:items].map do |repo|
        {
          name: repo[:name],
          description: repo[:description],
          url: repo[:html_url],
          stars: repo[:stargazers_count],
          language: repo[:language]
        }
      end

      {
        items: repos,
        metadata: {
          username: params[:username],
          total: repos.size
        }
      }
    end
  end
end

# Usage
result = Github::RepositoriesService.new(nil, params: {
  username: "rails",
  type: "owner"
}).call
```

## Best Practices

### 1. Use Scopes for Reusable Queries

```ruby
# In model
class Product < ApplicationRecord
  scope :active, -> { where(status: 'active') }
  scope :in_stock, -> { where('stock > ?', 0) }
  scope :recent, -> { where('created_at > ?', 1.week.ago) }
end

# In service
search_with do
  scope = model_class.active.in_stock
  scope = scope.recent if params[:recent]
  { items: scope }
end
```

### 2. Always Use Eager Loading

```ruby
# ❌ Bad: N+1 queries
search_with do
  { items: Product.all }
end

# ✅ Good: Eager load associations
search_with do
  { items: Product.includes(:category, :reviews, :images).all }
end
```

### 3. Limit Maximum Results

```ruby
schema do
  optional(:per_page).filled(:integer, gteq?: 1, lteq?: 100)  # Max 100
end

process_with do |data|
  per_page = [params[:per_page] || 20, 100].min  # Never exceed 100
  { items: data[:items].limit(per_page) }
end
```

### 4. Cache Expensive Queries

```ruby
class Product::IndexService < BetterService::IndexService
  cache_contexts :products, :filters

  search_with do
    # This will be cached
    { items: model_class.includes(:category).where(filters) }
  end
end
```

### 5. Validate Filter Parameters

```ruby
schema do
  optional(:status).maybe(:string, included_in?: %w[active inactive pending])
  optional(:sort_by).maybe(:string, included_in?: %w[name price created_at])
  optional(:min_price).maybe(:decimal, gteq?: 0)
  optional(:max_price).maybe(:decimal, gteq?: 0)
end
```

### 6. Provide Meaningful Metadata

```ruby
process_with do |data|
  items = data[:items]

  {
    items: items,
    metadata: {
      total: items.count,
      filters_applied: params.slice(:status, :category_id).compact,
      applied_at: Time.current
    }
  }
end
```

## Testing

### RSpec

```ruby
# spec/services/product/index_service_spec.rb
require 'rails_helper'

RSpec.describe Product::IndexService do
  let(:user) { create(:user) }
  let!(:products) { create_list(:product, 5, status: 'active') }
  let!(:inactive_products) { create_list(:product, 2, status: 'inactive') }

  describe '#call' do
    context 'without filters' do
      it 'returns all active products' do
        result = described_class.new(user, params: {}).call

        expect(result[:success]).to be true
        expect(result[:items].size).to eq(5)
      end
    end

    context 'with status filter' do
      it 'filters products by status' do
        result = described_class.new(user, params: { status: 'inactive' }).call

        expect(result[:items].size).to eq(2)
        expect(result[:items].map(&:status)).to all(eq('inactive'))
      end
    end

    context 'with search term' do
      let!(:laptop) { create(:product, name: 'Gaming Laptop', status: 'active') }

      it 'searches products by name' do
        result = described_class.new(user, params: { search: 'laptop' }).call

        expect(result[:items]).to include(laptop)
        expect(result[:items].size).to eq(1)
      end
    end

    context 'with pagination' do
      it 'paginates results' do
        result = described_class.new(user, params: {
          page: 1,
          per_page: 2
        }).call

        expect(result[:items].size).to eq(2)
        expect(result[:metadata][:page]).to eq(1)
        expect(result[:metadata][:per_page]).to eq(2)
      end
    end
  end

  describe 'authorization' do
    context 'when user is not active' do
      let(:inactive_user) { create(:user, status: 'inactive') }

      it 'raises authorization error' do
        expect {
          described_class.new(inactive_user, params: {}).call
        }.to raise_error(BetterService::Errors::Runtime::AuthorizationError)
      end
    end
  end

  describe 'caching' do
    it 'caches the results' do
      service = described_class.new(user, params: {})

      expect {
        service.call
      }.to change { Rails.cache.fetch('products:filters') }
    end

    it 'invalidates cache when product is created' do
      described_class.new(user, params: {}).call
      create(:product)

      # Cache should be invalidated
      expect(Rails.cache.exist?('products:filters')).to be false
    end
  end
end
```

### Minitest

```ruby
# test/services/product/index_service_test.rb
require 'test_helper'

class Product::IndexServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:regular_user)
    @products = create_list(:product, 5, status: 'active')
  end

  test "returns all products without filters" do
    result = Product::IndexService.new(@user, params: {}).call

    assert result[:success]
    assert_equal 5, result[:items].size
  end

  test "filters products by status" do
    inactive = create(:product, status: 'inactive')

    result = Product::IndexService.new(@user, params: { status: 'inactive' }).call

    assert_equal 1, result[:items].size
    assert_equal 'inactive', result[:items].first.status
  end

  test "searches products by name" do
    laptop = create(:product, name: 'Gaming Laptop')

    result = Product::IndexService.new(@user, params: { search: 'laptop' }).call

    assert_includes result[:items], laptop
  end

  test "paginates results" do
    result = Product::IndexService.new(@user, params: {
      page: 1,
      per_page: 2
    }).call

    assert_equal 2, result[:items].size
    assert_equal 1, result[:metadata][:page]
  end

  test "raises validation error for invalid params" do
    assert_raises BetterService::Errors::Runtime::ValidationError do
      Product::IndexService.new(@user, params: { page: -1 }).call
    end
  end
end
```

## Common Patterns

### Pattern 1: Dynamic Filtering

```ruby
search_with do
  scope = model_class.all

  # Apply each filter if present
  FILTERABLE_FIELDS.each do |field|
    scope = scope.where(field => params[field]) if params[field]
  end

  { items: scope }
end
```

### Pattern 2: Full-Text Search

```ruby
search_with do
  scope = model_class.all

  if params[:search].present?
    scope = scope.where(
      'name ILIKE :q OR description ILIKE :q OR tags ILIKE :q',
      q: "%#{params[:search]}%"
    )
  end

  { items: scope }
end
```

### Pattern 3: Multi-Tenant Scoping

```ruby
search_with do
  # Automatically scope to user's tenant
  scope = model_class.where(tenant_id: user.tenant_id)

  # Apply additional filters
  scope = scope.where(status: params[:status]) if params[:status]

  { items: scope }
end
```

---

**See also:**
- [Services Structure](01_services_structure.md)
- [ShowService](03_show_service.md)
- [Service Configurations](08_service_configurations.md)
- [Cache Invalidation](../advanced/cache-invalidation.md)
