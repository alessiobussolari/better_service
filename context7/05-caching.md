# Caching

Cache service results to avoid costly re-executions.

---

## How It Works

### Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        service.call()                           │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │     Cache enabled?           │
              │   (cache_key defined?)       │
              └──────────┬──────────┬────────┘
                         │          │
                      Yes│          │ No
                         │          │
              ┌──────────▼──────┐   │
              │ Generate cache  │   │
              │ key:            │   │
              │ key:user:md5    │   │
              └────────┬────────┘   │
                       │            │
              ┌────────▼─────────┐  │
              │ Cache valid?     │  │
              └────┬────────┬────┘  │
                   │        │       │
               Hit │        │ Miss  │
                   │        │       │
         ┌─────────▼───┐    │       │
         │ Return      │    │       │
         │ Result      │    │       │
         │ from cache  │    │       │
         │ (NO query,  │    │       │
         │ NO process) │    │       │
         └─────────────┘    │       │
                            │       │
              ┌─────────────▼───────▼─────────────────┐
              │        FULL EXECUTION                 │
              │                                       │
              │  1. search_with  → DB Query           │
              │  2. process_with → Transformations    │
              │  3. transform    → Presenter          │
              │  4. respond_with → Response format    │
              │                                       │
              │  Result: BetterService::Result        │
              └───────────────────┬───────────────────┘
                                  │
                    ┌─────────────▼─────────────┐
                    │ Cache enabled?            │
                    └──────┬──────────┬─────────┘
                           │          │
                        Yes│          │ No
                           │          │
              ┌────────────▼────────┐ │
              │ Store Result        │ │
              │ in Rails.cache      │ │
              │ (TTL: cache_ttl)    │ │
              └────────────┬────────┘ │
                           │          │
                           └────┬─────┘
                                │
                    ┌───────────▼────────────┐
                    │  Return Result         │
                    │  (resource + meta)     │
                    └────────────────────────┘
```

--------------------------------

## Configuration

### Enable Caching

```ruby
class Product::IndexService < Product::BaseService
  cache_key :products_list    # Enable cache with this identifier
  cache_ttl 15.minutes        # Cache duration (default: 15 minutes)
  cache_contexts [:products]  # Contexts for invalidation

  search_with do
    # This query executes ONLY on cache miss
    { items: Product.includes(:category).where(active: true).to_a }
  end
end
```

--------------------------------

## Performance Benefits

### Without Cache

```
Call 1: DB Query (50ms) + Process (20ms) = 70ms
Call 2: DB Query (50ms) + Process (20ms) = 70ms
Call 3: DB Query (50ms) + Process (20ms) = 70ms
Total: 210ms
```

### With Cache

```
Call 1: DB Query (50ms) + Process (20ms) + Cache write (1ms) = 71ms
Call 2: Cache read (1ms) = 1ms
Call 3: Cache read (1ms) = 1ms
Total: 73ms (3x faster!)
```

--------------------------------

## Cache Key

The cache key is composed of:

```
{cache_key}:{user_id}:{params_hash}

Example: products_list:user_123:a1b2c3d4
```

- **cache_key**: Service identifier
- **user_id**: User ID (or "global" if nil)
- **params_hash**: MD5 of parameters (different params = separate caches)

--------------------------------

## DSL Methods

### cache_key

Enable caching and define identifier.

```ruby
class Product::IndexService < Product::BaseService
  cache_key :products_list
end
```

--------------------------------

### cache_ttl

Cache duration (default: 15 minutes).

```ruby
class Product::IndexService < Product::BaseService
  cache_key :products_list
  cache_ttl 1.hour            # 1 hour
  cache_ttl 30.minutes        # 30 minutes
  cache_ttl 86400             # Seconds (24 hours)
end
```

--------------------------------

### cache_contexts

Contexts for automatic invalidation.

```ruby
class Product::IndexService < Product::BaseService
  cache_key :products_list
  cache_contexts [:products, :inventory]
end
```

--------------------------------

## Auto-Invalidation

Create/Update/Destroy services automatically invalidate cache.

```ruby
class Product::CreateService < Product::BaseService
  cache_contexts [:products]     # Contexts to invalidate
  auto_invalidate_cache true     # Default for CUD services

  # After create: invalidates all :products caches for this user
end
```

### Disable Auto-Invalidation

```ruby
class Product::CreateService < Product::BaseService
  auto_invalidate_cache false    # Manual management
end
```

--------------------------------

## Manual Invalidation

### Per User and Context

```ruby
# Invalidate :products cache for specific user
BetterService::CacheService.invalidate_for_context(user, :products)
```

### Global for Context

```ruby
# Invalidate :products cache for all users
BetterService::CacheService.invalidate_global(:products)
```

### All for User

```ruby
# Invalidate all caches for a user
BetterService::CacheService.invalidate_for_user(user)
```

### Specific Key

```ruby
# Invalidate a specific key
BetterService::CacheService.invalidate_key("products_list:user_123:abc")
```

--------------------------------

## Cache Invalidation Map

Configure cascade invalidation.

```ruby
# config/initializers/better_service.rb
BetterService.configure do |config|
  config.cache_invalidation_map = {
    products: [:inventory, :reports, :homepage],
    orders: [:user_orders, :reports, :dashboard],
    users: [:user_profile, :user_orders]
  }
end
```

### How It Works

```ruby
# When you invalidate :products
BetterService::CacheService.invalidate_for_context(user, :products)

# Automatically invalidated:
# - :products
# - :inventory
# - :reports
# - :homepage
```

--------------------------------

## Instrumentation Events

### Cache Events

```ruby
# Cache hit
ActiveSupport::Notifications.subscribe("cache.hit.better_service") do |name, start, finish, id, payload|
  Rails.logger.info "Cache HIT: #{payload[:service]} (key: #{payload[:cache_key]})"
end

# Cache miss
ActiveSupport::Notifications.subscribe("cache.miss.better_service") do |name, start, finish, id, payload|
  Rails.logger.info "Cache MISS: #{payload[:service]} (key: #{payload[:cache_key]})"
end
```

--------------------------------

## Best Practices

### When to Use Caching

```ruby
# Use caching for:
# - Index services with complex queries
# - Show services with rarely changing data
# - Frequently called services

class Dashboard::StatsService < ApplicationService
  cache_key :dashboard_stats
  cache_ttl 5.minutes           # Refresh every 5 minutes

  search_with do
    # Expensive aggregate queries
    {
      total_orders: Order.count,
      revenue: Order.sum(:total),
      top_products: Product.top_selling(10)
    }
  end
end
```

### When NOT to Use Caching

```ruby
# DON'T use caching for:
# - Create/Update/Destroy services (they invalidate, not cache)
# - Real-time data (prices, stock)
# - User-sensitive data

class Order::CreateService < Order::BaseService
  # NO cache_key - writes don't cache
  cache_contexts [:orders]      # But they invalidate orders cache
end
```

--------------------------------

## Complete Example

### IndexService with Cache

```ruby
class Product::IndexService < Product::BaseService
  performed_action :listed

  # Cache configuration
  cache_key :products_index
  cache_ttl 30.minutes
  cache_contexts [:products]

  schema do
    optional(:page).filled(:integer, gteq?: 1)
    optional(:per_page).filled(:integer, gteq?: 1, lteq?: 100)
    optional(:category_id).filled(:integer)
  end

  search_with do
    # Executed ONLY on cache miss
    scope = Product.includes(:category).active

    if params[:category_id]
      scope = scope.where(category_id: params[:category_id])
    end

    {
      items: scope.page(params[:page]).per(params[:per_page] || 20).to_a,
      total_count: scope.count
    }
  end

  process_with do |data|
    {
      items: data[:items],
      metadata: {
        page: params[:page] || 1,
        per_page: params[:per_page] || 20,
        total_count: data[:total_count]
      }
    }
  end
end

# First call: executes query, saves to cache
# Second call (same params): returns from cache instantly
```

### CreateService that Invalidates Cache

```ruby
class Product::CreateService < Product::BaseService
  performed_action :created
  with_transaction true

  # Invalidate cache after creation
  cache_contexts [:products]
  auto_invalidate_cache true    # Default

  schema do
    required(:name).filled(:string)
    required(:price).filled(:decimal, gt?: 0)
  end

  process_with do
    product = Product.create!(
      name: params[:name],
      price: params[:price],
      user: user
    )

    { resource: product }
  end

  # After success:
  # 1. Product created
  # 2. :products cache invalidated automatically
  # 3. Next IndexService will execute fresh query
end
```

--------------------------------
