# Concerns Reference

BetterService provides 7 powerful concerns that add cross-cutting functionality to your services. This reference covers all concerns in detail.

## Table of Contents

- [Overview](#overview)
- [Validatable](#validatable)
- [Authorizable](#authorizable)
- [Transactional](#transactional)
- [Presentable](#presentable)
- [Viewable](#viewable)
- [Cacheable](#cacheable)
- [Messageable](#messageable)

---

## Overview

### What are Concerns?

Concerns are modules that extend service functionality through Ruby's module inclusion system. They provide features like validation, authorization, transactions, caching, and more.

### Included by Default

All concerns are automatically included in `BetterService::Base`, which means every service has access to all concern features.

### How They Work

Concerns use Ruby hooks (`included`, `prepended`) and class attributes to extend services with DSL methods and runtime behavior.

---

## Validatable

**Purpose**: Parameter validation using Dry::Schema

**Phase**: Validation (during `initialize`, before `call`)

**Required**: Yes (all services MUST define a schema)

### Overview

The `Validatable` concern integrates [Dry::Schema](https://dry-rb.org/gems/dry-schema/) for parameter validation. All input parameters are validated against a defined schema **before** the service executes.

---

### DSL: `schema`

Define validation rules for service parameters.

**Syntax:**
```ruby
schema do
  required(:field_name).filled(:type, predicate?: value)
  optional(:field_name).maybe(:type)
end
```

**Example:**
```ruby
class Product::CreateService < BetterService::Services::CreateService
  schema do
    required(:name).filled(:string)
    required(:price).filled(:decimal, gt?: 0)
    optional(:description).maybe(:string)
    optional(:published).maybe(:bool)
  end
end
```

---

### Types

Common Dry::Schema types:

| Type | Description | Example |
|------|-------------|---------|
| `:string` | String value | `"Hello"` |
| `:integer` | Integer number | `42` |
| `:decimal` | Decimal number | `99.99` |
| `:float` | Float number | `3.14` |
| `:bool` | Boolean | `true`, `false` |
| `:date` | Date object | `Date.today` |
| `:time` | Time object | `Time.now` |
| `:hash` | Hash object | `{ key: "value" }` |
| `:array` | Array object | `[1, 2, 3]` |

---

### Predicates

Common validation predicates:

| Predicate | Description | Example |
|-----------|-------------|---------|
| `filled?` | Not nil and not empty | `required(:name).filled(:string)` |
| `gt?` | Greater than | `required(:age).filled(:integer, gt?: 18)` |
| `gteq?` | Greater than or equal | `required(:price).filled(:decimal, gteq?: 0)` |
| `lt?` | Less than | `required(:discount).filled(:integer, lt?: 100)` |
| `lteq?` | Less than or equal | `required(:quantity).filled(:integer, lteq?: 1000)` |
| `size?` | Exact size | `required(:code).filled(:string, size?: 6)` |
| `min_size?` | Minimum size | `required(:password).filled(:string, min_size?: 8)` |
| `max_size?` | Maximum size | `required(:username).filled(:string, max_size?: 20)` |
| `format?` | Regex match | `required(:email).filled(:string, format?: /@/)` |
| `included_in?` | In a list | `required(:status).filled(:string, included_in?: ["active", "inactive"])` |

---

### Validation Rules

#### Required Fields

```ruby
schema do
  required(:email).filled(:string)
  # Must be present and not empty
end
```

#### Optional Fields

```ruby
schema do
  optional(:nickname).maybe(:string)
  # Can be omitted or nil
end
```

#### Nested Hashes

```ruby
schema do
  required(:address).hash do
    required(:street).filled(:string)
    required(:city).filled(:string)
    required(:zip).filled(:string, format?: /^\d{5}$/)
  end
end
```

#### Arrays

```ruby
schema do
  required(:tags).filled(:array).each(:string)
  # Array of strings, must have at least one element
end
```

#### Custom Validation

```ruby
schema do
  required(:email).filled(:string)

  # Custom validation rule
  rule(:email) do
    key.failure("must be a valid email") unless value.include?("@")
  end
end
```

---

### Validation Errors

When validation fails, `ValidationError` is raised during `initialize`:

```ruby
begin
  service = Product::CreateService.new(user, params: {
    name: "",      # Invalid: must be filled
    price: -10     # Invalid: must be > 0
  })
rescue BetterService::Errors::Runtime::ValidationError => e
  e.context[:validation_errors]
  # => {
  #   name: ["must be filled"],
  #   price: ["must be greater than 0"]
  # }
end
```

---

### Empty Schema

If your service doesn't need parameters, define an empty schema:

```ruby
schema do
  # No parameters required
end
```

**Note**: You cannot omit the `schema` block entirely. It will raise `SchemaRequiredError`.

---

## Authorizable

**Purpose**: User permission checks

**Phase**: Authorization (start of `call`, before search)

**Required**: No (optional)

### Overview

The `Authorizable` concern provides the `authorize_with` DSL for checking user permissions before executing a service.

---

### DSL: `authorize_with`

Define authorization logic that executes before the search phase.

**Syntax:**
```ruby
authorize_with do
  # Return truthy value for authorized
  # Return falsy value for unauthorized
end
```

**Example:**
```ruby
class Product::UpdateService < BetterService::Services::UpdateService
  authorize_with do
    product = Product.find(params[:id])
    user.admin? || product.user_id == user.id
  end
end
```

---

### Authorization Patterns

#### Simple Role Check

```ruby
authorize_with do
  user.admin?
end
```

#### Resource Ownership

```ruby
authorize_with do
  resource = Product.find(params[:id])
  resource.user_id == user.id
end
```

#### Combined Conditions

```ruby
authorize_with do
  user.admin? || (user.verified? && user.subscription_active?)
end
```

#### Pundit Integration

```ruby
authorize_with do
  ProductPolicy.new(user, Product.find(params[:id])).update?
end
```

#### CanCanCan Integration

```ruby
authorize_with do
  Ability.new(user).can?(:destroy, Product)
end
```

---

### Authorization Failure

When authorization fails, `AuthorizationError` is raised during `call`:

```ruby
begin
  service.call
rescue BetterService::Errors::Runtime::AuthorizationError => e
  e.message  # => "Not authorized to perform this action"
  e.code     # => :unauthorized
end
```

---

### Allow Nil User

By default, services require a `user` object. To allow `nil`:

```ruby
class Public::IndexService < BetterService::Services::IndexService
  self._allow_nil_user = true

  schema do
    optional(:query).maybe(:string)
  end

  # No authorize_with needed
end
```

---

## Transactional

**Purpose**: Database transaction wrapping

**Phase**: Wraps the `process` method

**Required**: No (opt-in)

**Default**: Enabled for Create/Update/Destroy services

### Overview

The `Transactional` concern wraps the `process` method in a database transaction using `ActiveRecord::Base.transaction`. If any error occurs, all changes are rolled back.

---

### DSL: `with_transaction`

Enable or disable transaction wrapping.

**Syntax:**
```ruby
with_transaction true   # Enable
with_transaction false  # Disable
```

---

### Default Behavior

| Service Type | Transaction Default |
|--------------|---------------------|
| IndexService | OFF |
| ShowService | OFF |
| CreateService | ON |
| UpdateService | ON |
| DestroyService | ON |
| ActionService | OFF |

---

### Examples

#### Enable Transaction

```ruby
class Order::CompleteService < BetterService::Services::ActionService
  with_transaction true  # Enable for ActionService

  process_with do |data|
    order = Order.find(params[:id])
    order.update!(status: "completed")

    # If this fails, order update is rolled back
    Invoice.create!(order: order, amount: order.total)

    { resource: order }
  end
end
```

#### Disable Transaction

```ruby
class Product::CreateService < BetterService::Services::CreateService
  with_transaction false  # Disable for CreateService

  process_with do |data|
    # No transaction wrapping
    product = Product.create!(params)
    { resource: product }
  end
end
```

---

### How It Works

`Transactional` is **prepended** (not included) to wrap the `process` method:

```ruby
# Simplified implementation
module Transactional
  def process(data)
    if self.class._with_transaction
      ActiveRecord::Base.transaction do
        super  # Call original process method
      end
    else
      super
    end
  end
end
```

---

### Rollback Behavior

If any error occurs during `process`, the transaction rolls back:

```ruby
class Order::CreateService < BetterService::Services::CreateService
  process_with do |data|
    order = Order.create!(params)  # Persisted

    # This fails
    raise "Payment processor unavailable"

    # order is rolled back - not persisted
  end
end
```

---

## Presentable

**Purpose**: Data transformation

**Phase**: Transform phase (phase 3)

**Required**: No (optional)

### Overview

The `Presentable` concern provides the `transform_with` DSL for transforming data after the search phase.

---

### DSL: `transform_with`

Define data transformation logic.

**Syntax:**
```ruby
transform_with do |data|
  # Transform data
  # Return transformed hash
end
```

**Example:**
```ruby
class Product::IndexService < BetterService::Services::IndexService
  search_with do
    { items: Product.all.to_a }
  end

  transform_with do |data|
    products = data[:items].map do |product|
      {
        id: product.id,
        name: product.name.upcase,
        price: "$#{product.price}",
        available: product.stock > 0
      }
    end

    { items: products }
  end
end
```

---

### Use Cases

- Format prices, dates, phone numbers
- Add computed fields
- Aggregate data
- Filter sensitive fields
- Normalize structure

---

## Viewable

**Purpose**: View layer integration

**Phase**: Viewer phase (phase 5, optional)

**Required**: No (optional)

### Overview

The `Viewable` concern provides presenter/view configuration for services.

---

### DSL: `presenter`

Specify a presenter class for transforming data.

**Syntax:**
```ruby
presenter PresenterClass
```

**Example:**
```ruby
class Product::ShowService < BetterService::Services::ShowService
  presenter ProductPresenter

  search_with do
    { resource: Product.find(params[:id]) }
  end
end

class ProductPresenter
  def initialize(product)
    @product = product
  end

  def to_h
    {
      id: @product.id,
      name: @product.name,
      price_formatted: "$#{@product.price}",
      available: @product.stock > 0
    }
  end
end
```

---

## Cacheable

**Purpose**: Response caching

**Phase**: Wraps `call` method

**Required**: No (opt-in)

### Overview

The `Cacheable` concern enables automatic caching of service results with configurable keys, TTL, and invalidation contexts.

---

### DSL Methods

#### `cache_key`

Set the base cache key.

```ruby
cache_key "products_index"
```

#### `cache_ttl`

Set the time-to-live for cached results.

```ruby
cache_ttl 1.hour
cache_ttl 30.minutes
cache_ttl 1.day
```

#### `cache_contexts`

Define invalidation contexts.

```ruby
cache_contexts :products, :categories
```

---

### Example

```ruby
class Product::IndexService < BetterService::Services::IndexService
  cache_key "products_index"
  cache_ttl 1.hour
  cache_contexts :products, :sidebar

  schema do
    optional(:category).maybe(:string)
  end

  search_with do
    products = Product.all
    products = products.where(category: params[:category]) if params[:category]
    { items: products.to_a }
  end
end
```

---

### Cache Key Format

Generated cache keys follow this pattern:

```
{cache_key}:user_{user_id}:{param_hash}:{contexts}
```

**Example:**
```
products_index:user_123:abc123def:products,sidebar
```

---

### Cache Invalidation

Invalidate cached data using `BetterService::CacheService`:

```ruby
# Invalidate for user + context
BetterService::CacheService.invalidate_for_context(user, "products")

# Invalidate globally
BetterService::CacheService.invalidate_global("products")

# Invalidate all for user
BetterService::CacheService.invalidate_for_user(user)
```

See [Cache Invalidation Guide](advanced/cache-invalidation.md) for details.

---

### Helper Methods

Inside services with caching enabled:

```ruby
# Manually invalidate cache for current user
invalidate_cache_for(user)

# Check cache hit/miss
Rails.logger.info("Cache hit!") if cache_hit?
```

---

## Messageable

**Purpose**: Response message formatting

**Phase**: Respond phase (phase 6)

**Required**: No (included by default)

### Overview

The `Messageable` concern provides helper methods for formatting success and error messages.

---

### Helper Methods

#### `success_result`

Format a success response.

```ruby
success_result(message, data)
```

**Example:**
```ruby
respond_with do |data|
  success_result("Product created successfully", data)
end
```

**Returns:**
```ruby
{
  success: true,
  message: "Product created successfully",
  resource: <Product>,
  metadata: { action: :created }
}
```

---

#### `error_result`

Format an error response (rarely used with pure exception pattern).

```ruby
error_result(message, errors = {})
```

---

### Default Messages

Each service type has a default success message:

| Service | Default Message |
|---------|-----------------|
| IndexService | "Resources loaded successfully" |
| ShowService | "Resource loaded successfully" |
| CreateService | "Resource created successfully" |
| UpdateService | "Resource updated successfully" |
| DestroyService | "Resource deleted successfully" |
| ActionService | "Action completed successfully" |

---

### Custom Messages

Override in `respond_with`:

```ruby
respond_with do |data|
  success_result("Product published and notified customers", data)
end
```

---

## Summary Table

| Concern | Phase | Required | DSL Methods | Default |
|---------|-------|----------|-------------|---------|
| **Validatable** | Validation | ✅ Yes | `schema` | Required |
| **Authorizable** | Authorization | ❌ No | `authorize_with` | Not used |
| **Transactional** | Process | ❌ No | `with_transaction` | ON for Create/Update/Destroy |
| **Presentable** | Transform | ❌ No | `transform_with` | Not used |
| **Viewable** | Viewer | ❌ No | `presenter` | Not used |
| **Cacheable** | Call wrapper | ❌ No | `cache_key`, `cache_ttl`, `cache_contexts` | Not used |
| **Messageable** | Respond | ✅ Included | `success_result`, `error_result` | Included |

---

## Next Steps

- **[Getting Started](start/getting-started.md)** - Start building services
- **[Service Types](services/01_services_structure.md)** - Learn about service types
- **[Error Handling](advanced/error-handling.md)** - Handle errors effectively
- **[Cache Invalidation](advanced/cache-invalidation.md)** - Advanced caching strategies

---

**See Also:**
- [Configuration Guide](start/configuration.md)
- [Testing Guide](testing.md)
- [Workflows](workflows/01_workflows_introduction.md)
