# Cache Invalidation Guide

BetterService provides comprehensive cache management through the `BetterService::CacheService` module and the `Cacheable` concern. This guide covers advanced caching strategies and patterns.

## Table of Contents

- [Overview](#overview)
- [CacheService API](#cacheservice-api)
- [Invalidation Methods](#invalidation-methods)
- [Integration Patterns](#integration-patterns)
- [Use Cases](#use-cases)
- [Performance Considerations](#performance-considerations)
- [Best Practices](#best-practices)

---

## Overview

### What is Cache Invalidation?

Cache invalidation is the process of removing stale cached data when the underlying data changes. BetterService provides automatic and manual cache invalidation strategies.

### Key Features

- **Context-based invalidation** - Invalidate by user + context
- **Global invalidation** - Invalidate for all users
- **User-specific invalidation** - Invalidate all cache for one user
- **Async support** - Background invalidation with ActiveJob
- **Pattern matching** - Wildcard-based key deletion
- **Cache statistics** - Monitor cache usage

---

## CacheService API

All cache operations are available through `BetterService::CacheService`:

```ruby
BetterService::CacheService.invalidate_for_context(user, "products")
BetterService::CacheService.invalidate_global("sidebar")
BetterService::CacheService.invalidate_for_user(user)
BetterService::CacheService.invalidate_key("specific_key")
BetterService::CacheService.clear_all
```

---

## Invalidation Methods

### 1. Invalidate for Context

Delete cache for a specific user and context.

**Method**: `invalidate_for_context(user, context, async: false)`

**Parameters:**
- `user` - User object
- `context` - String context name
- `async` - Boolean, run in background (default: false)

**Example:**
```ruby
# Invalidate product cache for current user
BetterService::CacheService.invalidate_for_context(current_user, "products")

# Async invalidation
BetterService::CacheService.invalidate_for_context(current_user, "products", async: true)
```

**What it deletes:**
```
products_index:user_123:*:products
products_show:user_123:*:products
```

**Use when:**
- User creates/updates/deletes a resource
- Resource data changes for specific user
- User's view of a collection changes

---

### 2. Invalidate Globally

Delete cache for all users in a specific context.

**Method**: `invalidate_global(context, async: false)`

**Parameters:**
- `context` - String context name
- `async` - Boolean, run in background (default: false)

**Example:**
```ruby
# Invalidate sidebar cache for ALL users
BetterService::CacheService.invalidate_global("sidebar")

# Async invalidation
BetterService::CacheService.invalidate_global("navigation", async: true)
```

**What it deletes:**
```
*:sidebar
# Matches:
# - products_index:user_123:abc:sidebar
# - navigation_menu:user_456:def:sidebar
# - any_service:any_user:*:sidebar
```

**Use when:**
- Global settings change (app configuration)
- Public data changes (navigation, footer)
- System-wide updates

---

### 3. Invalidate for User

Delete all cached data for a specific user.

**Method**: `invalidate_for_user(user, async: false)`

**Parameters:**
- `user` - User object
- `async` - Boolean, run in background (default: false)

**Example:**
```ruby
# Invalidate all cache for user
BetterService::CacheService.invalidate_for_user(current_user)

# Async invalidation
BetterService::CacheService.invalidate_for_user(user, async: true)
```

**What it deletes:**
```
*:user_123:*
# Matches all cache keys containing user_123
```

**Use when:**
- User role/permissions change
- User preferences updated
- User logs out (optional)
- User account deleted

---

### 4. Invalidate Specific Key

Delete a single cache key.

**Method**: `invalidate_key(key)`

**Parameters:**
- `key` - String cache key

**Example:**
```ruby
BetterService::CacheService.invalidate_key("products_index:user_123:abc:products")
```

**Use when:**
- You know the exact key to invalidate
- Fine-grained cache control
- Custom cache keys

---

### 5. Clear All Cache

**⚠️ WARNING**: Clears ALL BetterService cache.

**Method**: `clear_all`

**Example:**
```ruby
# Use with caution!
BetterService::CacheService.clear_all
```

**Use when:**
- Development/testing only
- After major data migrations
- Emergency cache reset

**DO NOT use in production** unless absolutely necessary.

---

## Integration Patterns

### Pattern 1: ActiveRecord Callbacks

Automatically invalidate cache when models change.

#### After Commit

```ruby
class Product < ApplicationRecord
  after_commit :invalidate_product_cache, on: [:create, :update, :destroy]

  private

  def invalidate_product_cache
    # Invalidate for all users
    BetterService::CacheService.invalidate_global("products")

    # Or invalidate only for product owner
    BetterService::CacheService.invalidate_for_context(user, "products")
  end
end
```

**Why `after_commit`?**
- Ensures DB transaction completed
- Prevents cache invalidation if transaction rolls back
- Works correctly with services that use transactions

---

#### Conditional Invalidation

```ruby
class Article < ApplicationRecord
  after_commit :invalidate_public_cache, if: :published?
  after_update :invalidate_author_cache, if: :saved_change_to_published?

  private

  def invalidate_public_cache
    # Only invalidate public cache for published articles
    BetterService::CacheService.invalidate_global("articles")
  end

  def invalidate_author_cache
    # Invalidate author's cache when publish status changes
    BetterService::CacheService.invalidate_for_context(author, "articles")
  end
end
```

---

### Pattern 2: Service-Based Invalidation

Invalidate cache explicitly in services.

#### In Process Phase

```ruby
class Product::CreateService < BetterService::Services::CreateService
  cache_contexts :products, :sidebar

  process_with do |data|
    product = user.products.create!(params)

    # Automatic invalidation for configured contexts
    invalidate_cache_for(user)  # Invalidates :products and :sidebar

    { resource: product }
  end
end
```

---

#### Manual Invalidation

```ruby
class Product::BulkUpdateService < BetterService::Services::ActionService
  process_with do |data|
    Product.where(id: params[:ids]).update_all(status: params[:status])

    # Manual global invalidation
    BetterService::CacheService.invalidate_global("products")

    { resource: { updated: params[:ids].count } }
  end
end
```

---

### Pattern 3: Controller-Based Invalidation

Invalidate cache in controllers for non-service actions.

```ruby
class ProductsController < ApplicationController
  def create
    @product = Product.create!(product_params)

    # Invalidate cache after creation
    BetterService::CacheService.invalidate_for_context(current_user, "products")

    redirect_to @product
  end

  def bulk_update
    Product.where(id: params[:ids]).update_all(status: params[:status])

    # Global invalidation for bulk operations
    BetterService::CacheService.invalidate_global("products")

    redirect_to products_path
  end
end
```

---

### Pattern 4: Background Jobs

Invalidate cache asynchronously for better performance.

#### Using Async Option

```ruby
# Queues a background job
BetterService::CacheService.invalidate_for_context(
  current_user,
  "products",
  async: true
)
```

**Requires**: ActiveJob configured in your Rails app.

---

#### Custom Job

```ruby
class InvalidateCacheJob < ApplicationJob
  queue_as :default

  def perform(user_id, context)
    user = User.find(user_id)
    BetterService::CacheService.invalidate_for_context(user, context)
  end
end

# In your service or controller
InvalidateCacheJob.perform_later(user.id, "products")
```

---

### Pattern 5: Scheduled Invalidation

Clear cache on a schedule for time-sensitive data.

```ruby
# lib/tasks/cache.rake
namespace :cache do
  desc "Clear product cache every hour"
  task invalidate_products: :environment do
    BetterService::CacheService.invalidate_global("products")
  end
end
```

```bash
# config/schedule.rb (whenever gem)
every 1.hour do
  rake "cache:invalidate_products"
end
```

---

## Use Cases

### Use Case 1: E-commerce Product Updates

**Scenario**: When a product is updated, invalidate cache for:
- Product detail page
- Product listings
- Category pages
- Search results

**Implementation:**
```ruby
class Product < ApplicationRecord
  belongs_to :category
  belongs_to :user

  after_commit :invalidate_caches, on: [:update, :destroy]

  private

  def invalidate_caches
    # Invalidate for product owner
    BetterService::CacheService.invalidate_for_context(user, "products")

    # Invalidate category cache globally (public data)
    BetterService::CacheService.invalidate_global("categories")

    # Invalidate search cache globally
    BetterService::CacheService.invalidate_global("search")
  end
end
```

---

### Use Case 2: User Permission Changes

**Scenario**: When a user's role changes, invalidate all their cached data.

**Implementation:**
```ruby
class User < ApplicationRecord
  after_update :invalidate_user_cache, if: :saved_change_to_role?

  private

  def invalidate_user_cache
    # Invalidate ALL cache for this user
    BetterService::CacheService.invalidate_for_user(self)
  end
end
```

---

### Use Case 3: Global Settings Update

**Scenario**: When admin updates site-wide settings, invalidate cache for all users.

**Implementation:**
```ruby
class Settings::UpdateService < BetterService::Services::UpdateService
  process_with do |data|
    Setting.update!(params)

    # Invalidate sidebar for all users
    BetterService::CacheService.invalidate_global("sidebar")

    # Invalidate navigation for all users
    BetterService::CacheService.invalidate_global("navigation")

    { resource: Setting.all }
  end
end
```

---

### Use Case 4: Bulk Operations

**Scenario**: After importing 1000 products, invalidate cache once (not 1000 times).

**Implementation:**
```ruby
class Product::BulkImportService < BetterService::Services::ActionService
  process_with do |data|
    products = []

    CSV.foreach(params[:file_path]) do |row|
      products << Product.create!(
        name: row[0],
        price: row[1]
      )
    end

    # Single cache invalidation after all imports
    BetterService::CacheService.invalidate_global("products", async: true)

    { resource: { imported: products.count } }
  end
end
```

---

## Performance Considerations

### Cache Store Compatibility

**Pattern-based deletion** (`delete_matched`) support:

| Cache Store | Supported | Performance |
|-------------|-----------|-------------|
| MemoryStore | ✅ Full | Excellent |
| RedisStore | ✅ Full | Excellent |
| RedisCacheStore | ✅ Full | Excellent |
| MemcachedStore | ⚠️ Limited | Poor |
| FileStore | ⚠️ Limited | Poor |
| NullStore | ⚠️ No-op | N/A |

**Recommendation**: Use Redis for production.

---

### Async vs Sync Invalidation

#### Sync Invalidation (Default)

```ruby
BetterService::CacheService.invalidate_for_context(user, "products")
```

**Pros:**
- Immediate consistency
- No job queue overhead
- Simpler debugging

**Cons:**
- Blocks request
- Slower for large key sets

**Use when:**
- Development/testing
- Small cache sizes
- Immediate consistency required

---

#### Async Invalidation

```ruby
BetterService::CacheService.invalidate_for_context(user, "products", async: true)
```

**Pros:**
- Non-blocking
- Better user experience
- Handles large cache sizes

**Cons:**
- Temporary stale cache
- Requires ActiveJob
- More complex debugging

**Use when:**
- Production with high traffic
- Large cache key sets
- Eventual consistency acceptable

---

### Invalidation Frequency

**Too frequent:**
- Cache never hits
- Wasted memory
- Poor performance

**Too infrequent:**
- Stale data
- Incorrect results
- User confusion

**Balance:**
- Invalidate only when data changes
- Use appropriate granularity (user vs global)
- Prefer specific context over clear_all

---

## Best Practices

### 1. Use Specific Contexts

```ruby
# ✅ Good - specific contexts
cache_contexts :products, :categories

# ❌ Bad - generic context
cache_contexts :data
```

---

### 2. Invalidate in Callbacks

```ruby
# ✅ Good - automatic invalidation
class Product < ApplicationRecord
  after_commit :invalidate_cache, on: [:create, :update, :destroy]
end

# ❌ Bad - manual invalidation everywhere
Product.create!(params)
BetterService::CacheService.invalidate_global("products")
```

---

### 3. Use after_commit, Not after_save

```ruby
# ✅ Good - waits for transaction
after_commit :invalidate_cache

# ❌ Bad - may invalidate before commit
after_save :invalidate_cache
```

---

### 4. Prefer User-Specific Over Global

```ruby
# ✅ Good - only affects one user
BetterService::CacheService.invalidate_for_context(user, "products")

# ⚠️ Use sparingly - affects all users
BetterService::CacheService.invalidate_global("products")
```

---

### 5. Use Async for Bulk Operations

```ruby
# ✅ Good - non-blocking
Product.bulk_import!
BetterService::CacheService.invalidate_global("products", async: true)

# ❌ Bad - blocks for large caches
BetterService::CacheService.invalidate_global("products")
```

---

### 6. Document Cache Dependencies

```ruby
class Product::IndexService < BetterService::Services::IndexService
  cache_key "products_index"
  cache_ttl 1.hour

  # CACHE DEPENDENCIES:
  # - Invalidated by: Product create/update/destroy
  # - Invalidated by: Category update (affects filtering)
  # - Context: :products
  cache_contexts :products, :categories
end
```

---

### 7. Monitor Cache Hit Rates

```ruby
# Enable stats in config/initializers/better_service.rb
config.stats_subscriber_enabled = true

# Check cache stats
stats = BetterService::Subscribers::StatsSubscriber.stats
cache_stats = stats[:cache]

cache_stats[:hits]    # => 1234
cache_stats[:misses]  # => 123
cache_stats[:hit_rate] # => 0.909 (90.9%)
```

**Target hit rates:**
- **>80%**: Good
- **60-80%**: Acceptable
- **<60%**: Review cache strategy

---

## Utilities

### Check Cache Existence

```ruby
if BetterService::CacheService.exist?("products_index:user_123:abc:products")
  # Key exists
end
```

---

### Fetch with Caching

```ruby
result = BetterService::CacheService.fetch("my_key", expires_in: 1.hour) do
  expensive_computation
end
```

---

### Get Cache Statistics

```ruby
stats = BetterService::CacheService.stats
# => {
#   cache_store: "ActiveSupport::Cache::RedisStore",
#   supports_pattern_deletion: true,
#   supports_async: true
# }
```

---

## Troubleshooting

### Cache Not Invalidating

**Check:**
1. Is cache store supported? (Redis recommended)
2. Are callbacks firing? (use `after_commit`)
3. Is ActiveJob configured? (for async)
4. Are contexts correctly configured?

**Debug:**
```ruby
# Enable logging
config.log_subscriber_enabled = true
config.log_subscriber_level = :debug

# Check cache keys
Rails.cache.fetch("test_key", expires_in: 1.hour) { "value" }
BetterService::CacheService.exist?("test_key")  # => true
```

---

### Cache Keys Not Matching

**Problem**: Pattern doesn't match expected keys.

**Solution**: Verify cache key format:
```ruby
service = Product::IndexService.new(user, params: {})
key = service.send(:cache_key_with_version)
# => "products_index:user_123:abc123:products"

# Invalidate with correct context
BetterService::CacheService.invalidate_for_context(user, "products")
```

---

## Next Steps

- **[Cacheable Concern](../concerns-reference.md#cacheable)** - Enable caching in services
- **[Service Configuration](../services/08_service_configurations.md)** - Configure cache settings
- **[Testing](../testing.md)** - Test cache behavior

---

**See Also:**
- [Getting Started](../start/getting-started.md)
- [Configuration Guide](../start/configuration.md)
- [Service Types](../services/01_services_structure.md)
