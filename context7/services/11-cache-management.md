# Cache Management Examples

## Enable Cache for Index
Cache collection queries.

```ruby
class Product::IndexService < BetterService::IndexService
  model_class Product
  cache_contexts :products

  search_with do
    { items: model_class.all }
  end
end

# First call: queries database, stores in cache
# Second call: returns cached results
```

## Invalidate Cache on Create
Clear caches when creating resources.

```ruby
class Product::CreateService < BetterService::CreateService
  model_class Product
  cache_contexts :products

  process_with do |data|
    resource = model_class.create!(params)

    # Invalidate :products cache for this user
    invalidate_cache_for(user)

    { resource: resource }
  end
end
```

## Multiple Cache Contexts
Invalidate multiple related caches.

```ruby
class Product::CreateService < BetterService::CreateService
  model_class Product
  cache_contexts :products, :category_products, :featured_products

  process_with do |data|
    resource = model_class.create!(params)

    # Invalidates all three cache contexts
    invalidate_cache_for(user)

    { resource: resource }
  end
end
```

## Cache for Show Service
Cache individual resource lookups.

```ruby
class Product::ShowService < BetterService::ShowService
  model_class Product
  cache_contexts :product

  search_with do
    { resource: model_class.includes(:category, :reviews).find(params[:id]) }
  end
end

# Results cached by user and product ID
```

## Conditional Cache Invalidation
Invalidate only when specific fields change.

```ruby
class Product::UpdateService < BetterService::UpdateService
  model_class Product
  cache_contexts :products, :product_prices

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    product = data[:resource]
    price_changed = product.price != params[:price]

    product.update!(params.except(:id))

    if price_changed
      # Invalidate price-specific caches
      invalidate_cache_for(user, contexts: [:product_prices])
    else
      # Invalidate general product cache
      invalidate_cache_for(user, contexts: [:products])
    end

    { resource: product }
  end
end
```

## Cross-User Cache Invalidation
Invalidate caches for multiple users.

```ruby
class Product::UpdateService < BetterService::UpdateService
  model_class Product
  cache_contexts :products

  process_with do |data|
    product = data[:resource]
    product.update!(params.except(:id))

    # Invalidate for current user
    invalidate_cache_for(user)

    # Also invalidate for product owner if different
    if product.user != user
      invalidate_cache_for(product.user)
    end

    { resource: product }
  end
end
```

## Cache with Filters
Cache varies by query parameters.

```ruby
class Product::IndexService < BetterService::IndexService
  model_class Product
  cache_contexts :products

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

# Different cache keys for different filters:
# user:123:products:category_id=5
# user:123:products:category_id=5:status=active
```

## Global Cache Invalidation
Clear caches for all users (use sparingly).

```ruby
class Product::CreateService < BetterService::CreateService
  model_class Product

  process_with do |data|
    resource = model_class.create!(params)

    # Invalidate for all users (expensive!)
    Rails.cache.delete_matched("*:products:*")

    { resource: resource }
  end
end
```

## No Cache for Sensitive Data
Disable caching for sensitive operations.

```ruby
class Payment::IndexService < BetterService::IndexService
  model_class Payment
  # NO cache_contexts - don't cache sensitive data

  search_with do
    { items: user.payments }
  end
end
```

## Cache with Presenter
Cache formatted results.

```ruby
class Product::IndexService < BetterService::IndexService
  model_class Product
  cache_contexts :products
  presenter ProductPresenter

  search_with do
    { items: model_class.includes(:category).all }
  end
end

# Caches the presented (formatted) results
```
