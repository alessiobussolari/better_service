# Service Configurations

## Overview

This guide covers all configuration options available across all service types. These configurations control behavior like caching, transactions, presenters, and more.

## Table of Contents

1. [Model Configuration](#model-configuration)
2. [Schema Configuration](#schema-configuration)
3. [Authorization Configuration](#authorization-configuration)
4. [Cache Configuration](#cache-configuration)
5. [Transaction Configuration](#transaction-configuration)
6. [Presenter Configuration](#presenter-configuration)
7. [User Configuration](#user-configuration)
8. [Action Configuration](#action-configuration)
9. [DSL Methods](#dsl-methods)

---

## Model Configuration

### model_class

Specifies the ActiveRecord model the service operates on.

```ruby
class Product::IndexService < BetterService::IndexService
  model_class Product
end
```

**Usage:**
- Required for all services except ActionService
- Enables automatic queries and finders
- Provides `model_class` method in service context

**When to use:**
- CRUD operations (Index, Show, Create, Update, Destroy)
- When service operates on a single model

**When not to use:**
- ActionService with no primary model
- Services operating on multiple unrelated models

---

## Schema Configuration

### schema

Defines parameter validation using Dry::Schema.

```ruby
class Product::CreateService < BetterService::CreateService
  schema do
    required(:name).filled(:string)
    required(:price).filled(:decimal, gt?: 0)
    optional(:description).maybe(:string)
  end
end
```

**Basic Types:**
```ruby
schema do
  # String
  required(:name).filled(:string)
  optional(:bio).maybe(:string)

  # Integer
  required(:age).filled(:integer, gteq?: 18)
  optional(:count).maybe(:integer, lteq?: 100)

  # Decimal/Float
  required(:price).filled(:decimal, gt?: 0)
  optional(:discount).maybe(:float, gteq?: 0, lteq?: 1)

  # Boolean
  required(:active).filled(:bool)
  optional(:featured).maybe(:bool)

  # Date/Time
  required(:start_date).filled(:date)
  optional(:published_at).maybe(:time)

  # Array
  required(:tag_ids).array(:integer)
  optional(:categories).array(:string)

  # Hash
  optional(:metadata).hash do
    required(:key).filled(:string)
    optional(:value).maybe(:string)
  end
end
```

**Advanced Validations:**
```ruby
schema do
  # String format
  required(:email).filled(:string, format?: /@/)
  required(:slug).filled(:string, format?: /\A[a-z0-9-]+\z/)

  # String size
  required(:password).filled(:string, min_size?: 8, max_size?: 100)
  optional(:bio).maybe(:string, max_size?: 500)

  # Included in list
  required(:status).filled(:string, included_in?: %w[draft published archived])
  optional(:role).maybe(:string, included_in?: %w[user admin moderator])

  # Number ranges
  required(:quantity).filled(:integer, gteq?: 1, lteq?: 100)
  required(:price).filled(:decimal, gt?: 0, lt?: 10000)

  # Custom rules
  rule(:password, :password_confirmation) do
    if values[:password] != values[:password_confirmation]
      key(:password_confirmation).failure('must match password')
    end
  end

  rule(:start_date, :end_date) do
    if values[:start_date] && values[:end_date]
      if values[:start_date] > values[:end_date]
        key(:end_date).failure('must be after start date')
      end
    end
  end
end
```

**Nested Schemas:**
```ruby
schema do
  required(:user).hash do
    required(:email).filled(:string, format?: /@/)
    required(:name).filled(:string)

    optional(:profile).hash do
      optional(:bio).maybe(:string)
      optional(:avatar_url).maybe(:string, format?: URI::DEFAULT_PARSER.make_regexp)
    end
  end

  optional(:addresses).array(:hash) do
    required(:street).filled(:string)
    required(:city).filled(:string)
    required(:zip).filled(:string)
  end
end
```

---

## Authorization Configuration

### authorize_with

Defines authorization rules that run before service execution.

```ruby
class Product::UpdateService < BetterService::UpdateService
  authorize_with do
    resource = model_class.find(params[:id])
    user.admin? || resource.user_id == user.id
  end
end
```

**Common Patterns:**

**1. Role-Based Authorization:**
```ruby
authorize_with do
  user.admin? || user.has_role?(:manager)
end
```

**2. Ownership Authorization:**
```ruby
authorize_with do
  resource = model_class.find(params[:id])
  resource.user_id == user.id
end
```

**3. Permission-Based Authorization:**
```ruby
authorize_with do
  user.can?(:create, Product)
end
```

**4. Conditional Authorization:**
```ruby
authorize_with do
  resource = model_class.find(params[:id])

  case resource.visibility
  when 'public'
    true
  when 'private'
    resource.user_id == user.id
  when 'team'
    resource.team.member?(user)
  else
    user.admin?
  end
end
```

**5. Complex Rules:**
```ruby
authorize_with do
  order = model_class.find(params[:id])

  # Users can cancel own pending/confirmed orders
  if user.customer?
    order.user_id == user.id &&
      params[:status] == 'cancelled' &&
      ['pending', 'confirmed'].include?(order.status)
  else
    # Admins can do anything
    user.admin?
  end
end
```

**Error Handling:**
```ruby
# In controller
begin
  result = MyService.new(current_user, params: params).call
rescue BetterService::Errors::Runtime::AuthorizationError => e
  render json: { error: "Access denied" }, status: :forbidden
end
```

---

## Cache Configuration

### cache_contexts

Defines cache contexts for automatic invalidation.

```ruby
class Product::IndexService < BetterService::IndexService
  cache_contexts :products, :category_products
end
```

**How It Works:**

1. **Caching happens automatically** for read operations (Index, Show)
2. **Invalidation happens automatically** when you call `invalidate_cache_for(user)`
3. **Cache keys** are built from: user ID + context + params

**Basic Usage:**
```ruby
class Product::IndexService < BetterService::IndexService
  cache_contexts :products

  search_with do
    { items: model_class.all }
  end
  # Results cached under "user:123:products:..."
end

class Product::CreateService < BetterService::CreateService
  cache_contexts :products

  process_with do |data|
    product = model_class.create!(params)

    # Invalidates all :products caches for this user
    invalidate_cache_for(user)

    { resource: product }
  end
end
```

**Multiple Contexts:**
```ruby
class Product::ShowService < BetterService::ShowService
  # Invalidate multiple related caches
  cache_contexts :product, :products, :category_products

  process_with do |data|
    # ...
    invalidate_cache_for(user)
    # Clears: product, products, and category_products caches
  end
end
```

**Selective Invalidation:**
```ruby
process_with do |data|
  product = data[:resource]

  # Conditionally invalidate
  if product.price_changed?
    invalidate_cache_for(user, contexts: [:product_prices])
  else
    invalidate_cache_for(user, contexts: [:products])
  end

  { resource: product }
end
```

**Cross-User Invalidation:**
```ruby
process_with do |data|
  product = data[:resource]

  # Invalidate for current user
  invalidate_cache_for(user)

  # Also invalidate for product owner
  if product.user != user
    invalidate_cache_for(product.user)
  end

  { resource: product }
end
```

**Global Invalidation:**
```ruby
process_with do |data|
  # Invalidate for all users (use sparingly!)
  Rails.cache.delete_matched("*:products:*")

  { resource: data[:resource] }
end
```

See [Cache Invalidation Guide](../advanced/cache-invalidation.md) for advanced patterns.

---

## Transaction Configuration

### _transactional

Controls whether operations run in database transactions.

```ruby
class Product::CreateService < BetterService::CreateService
  self._transactional = true  # Default for Create, Update, Destroy
end

class Product::IndexService < BetterService::IndexService
  self._transactional = false  # Default for Index, Show
end
```

**Default Values by Service Type:**

| Service Type | Default Transaction | Reason |
|-------------|-------------------|---------|
| IndexService | `false` | Read-only operation |
| ShowService | `false` | Read-only operation |
| CreateService | `true` | Needs rollback on failure |
| UpdateService | `true` | Needs rollback on failure |
| DestroyService | `true` | Needs rollback on failure |
| ActionService | Configurable | Depends on use case |

**When Transactions Are Useful:**

```ruby
# ✅ Create with associations
class Order::CreateService < BetterService::CreateService
  self._transactional = true

  process_with do |data|
    order = Order.create!(params)
    order.items.create!(item_params)
    order.charge_payment!
    # If any step fails, everything rolls back
    { resource: order }
  end
end

# ✅ Update with dependencies
class Product::UpdateService < BetterService::UpdateService
  self._transactional = true

  process_with do |data|
    product = data[:resource]
    product.update!(params)
    product.variants.each(&:recalculate_price!)
    # All or nothing
    { resource: product }
  end
end
```

**When to Disable Transactions:**

```ruby
# ✅ Read-only operations
class Report::GenerateService < BetterService::ActionService
  self._transactional = false

  process_with do |data|
    # No database writes, no transaction needed
    { resource: generate_report }
  end
end

# ✅ External API calls
class Email::SendService < BetterService::ActionService
  self._transactional = false

  process_with do |data|
    # External service, can't rollback anyway
    EmailProvider.send(params)
    { resource: true }
  end
end
```

**Manual Transactions:**

```ruby
self._transactional = false

process_with do |data|
  # Fine-grained control
  ActiveRecord::Base.transaction do
    # Only this part in transaction
    create_records
  end

  # This part outside transaction
  send_notifications

  { resource: data }
end
```

---

## Presenter Configuration

### presenter

Applies a presenter to format service output.

```ruby
class Product::ShowService < BetterService::ShowService
  presenter ProductPresenter
end
```

**Presenter Requirements:**

Presenters must implement a `present` class method:

```ruby
class ProductPresenter
  def self.present(product)
    {
      id: product.id,
      name: product.name,
      price: product.price.to_f,
      category: product.category.name,
      images: product.images.map(&:url)
    }
  end
end
```

**For Collections (IndexService):**

```ruby
class ProductPresenter
  def self.present(product)
    {
      id: product.id,
      name: product.name,
      price: format_price(product.price)
    }
  end

  private

  def self.format_price(price)
    "$#{price.round(2)}"
  end
end

# Applied to each item
class Product::IndexService < BetterService::IndexService
  presenter ProductPresenter

  # Returns:
  # {
  #   items: [
  #     { id: 1, name: "Product 1", price: "$99.99" },
  #     { id: 2, name: "Product 2", price: "$149.99" }
  #   ]
  # }
end
```

**Conditional Presentation:**

```ruby
class Product::ShowService < BetterService::ShowService
  model_class Product

  # Don't always use presenter
  def presenter_class
    params[:detailed] ? DetailedProductPresenter : ProductPresenter
  end
end
```

**Instance-Based Presenters:**

```ruby
class UserPresenter
  def initialize(user, current_user:)
    @user = user
    @current_user = current_user
  end

  def present
    {
      id: @user.id,
      name: @user.name,
      email: show_email? ? @user.email : nil
    }
  end

  private

  def show_email?
    @current_user.admin? || @current_user == @user
  end
end

# Usage in service
class User::ShowService < BetterService::ShowService
  def transform(data)
    presenter = UserPresenter.new(data[:resource], current_user: user)
    { resource: presenter.present }
  end
end
```

---

## User Configuration

### _allow_nil_user

Allows services to be called without a user.

```ruby
class Public::ArticleIndexService < BetterService::IndexService
  self._allow_nil_user = true

  search_with do
    { items: Article.published }
  end
end

# Usage
result = Public::ArticleIndexService.new(nil, params: {}).call
```

**Default Behavior:**

```ruby
# ❌ Raises NilUserError by default
MyService.new(nil, params: {}).call

# ✅ Allow nil user
class MyService < BetterService::IndexService
  self._allow_nil_user = true
end

MyService.new(nil, params: {}).call  # Works!
```

**Use Cases:**

```ruby
# Public APIs
class Api::V1::ProductsService < BetterService::IndexService
  self._allow_nil_user = true

  search_with do
    { items: Product.publicly_available }
  end
end

# Background jobs
class Report::GenerateService < BetterService::ActionService
  self._allow_nil_user = true

  process_with do |data|
    { resource: generate_monthly_report }
  end
end

# Webhooks
class Webhook::ProcessService < BetterService::ActionService
  self._allow_nil_user = true

  process_with do |data|
    { resource: process_webhook(params) }
  end
end
```

**Conditional Logic Based on User:**

```ruby
class Product::IndexService < BetterService::IndexService
  self._allow_nil_user = true

  search_with do
    scope = model_class.all

    # Show more to authenticated users
    if user.present?
      scope = user.admin? ? scope : scope.where(visible: true)
    else
      scope = scope.where(publicly_available: true)
    end

    { items: scope }
  end
end
```

---

## Action Configuration

### action_name

Defines custom action identifier for ActionService.

```ruby
class Order::ApproveService < BetterService::ActionService
  action_name :approve
end

result = Order::ApproveService.new(user, params: { id: 1 }).call
result[:metadata][:action]  # => :approve
```

**Usage:**

```ruby
class Article::PublishService < BetterService::ActionService
  action_name :publish
end

class Article::ArchiveService < BetterService::ActionService
  action_name :archive
end

class Payment::RefundService < BetterService::ActionService
  action_name :refund
end
```

**In Metadata:**

```ruby
result = Order::ApproveService.new(user, params: { id: 1 }).call

result[:metadata]
# => {
#   action: :approve,
#   # ... other metadata
# }
```

---

## DSL Methods

### search_with

Defines data loading logic.

```ruby
search_with do
  { items: Product.all }
end

# Or with block parameter
search_with do |params|
  { items: Product.where(status: params[:status]) }
end
```

### process_with

Defines business logic and transformations.

```ruby
process_with do |data|
  resource = model_class.create!(params)
  { resource: resource }
end
```

### respond_with

Customizes final response format.

```ruby
respond_with do |data|
  success_result("Operation successful", data)
end

# With custom message
respond_with do |data|
  count = data[:items].size
  success_result("Found #{count} items", data)
end
```

### Helper Methods

**success_result**

Formats a successful response:

```ruby
success_result("Message", data_hash)

# Returns:
# {
#   success: true,
#   message: "Message",
#   metadata: { action: :index, ... },
#   ...data_hash
# }
```

**invalidate_cache_for**

Invalidates cache for a user:

```ruby
# Invalidate all contexts
invalidate_cache_for(user)

# Invalidate specific contexts
invalidate_cache_for(user, contexts: [:products])
invalidate_cache_for(user, contexts: [:products, :categories])
```

---

## Complete Configuration Example

Here's a service using most available configurations:

```ruby
module Product
  class UpdateService < BetterService::UpdateService
    # Model configuration
    model_class Product

    # Cache configuration
    cache_contexts :products, :product_details, :category_products

    # Presenter configuration
    presenter ProductPresenter

    # Transaction configuration (default for UpdateService)
    self._transactional = true

    # Schema configuration
    schema do
      required(:id).filled(:integer)
      optional(:name).maybe(:string, min_size?: 3)
      optional(:price).maybe(:decimal, gt?: 0)
      optional(:category_id).maybe(:integer)
      optional(:tag_ids).array(:integer)

      rule(:price) do
        if key? && values[:price] && values[:price] > 10000
          key.failure('cannot exceed $10,000')
        end
      end
    end

    # Authorization configuration
    authorize_with do
      product = model_class.find(params[:id])
      user.admin? || product.user_id == user.id
    end

    # Search phase
    search_with do
      product = model_class.includes(:category, :tags).find(params[:id])
      { resource: product }
    end

    # Process phase
    process_with do |data|
      product = data[:resource]

      # Update base attributes
      product.update!(params.except(:id, :tag_ids))

      # Update associations
      if params[:tag_ids]
        product.tags = Tag.where(id: params[:tag_ids])
      end

      # Invalidate caches
      invalidate_cache_for(user)

      # Track change
      Analytics.track('product_updated', {
        product_id: product.id,
        user_id: user.id
      })

      { resource: product }
    end

    # Response phase
    respond_with do |data|
      success_result("#{data[:resource].name} updated successfully", data)
    end
  end
end
```

---

## Configuration Best Practices

### 1. Always Define Schema

```ruby
# ✅ Good: Explicit validation
schema do
  required(:id).filled(:integer)
  optional(:name).maybe(:string)
end

# ❌ Bad: No validation
# (params are not validated)
```

### 2. Use Authorization for Protected Resources

```ruby
# ✅ Good: Authorization check
authorize_with do
  resource = model_class.find(params[:id])
  resource.user_id == user.id
end

# ❌ Bad: No authorization
# Anyone can modify any resource
```

### 3. Configure Caching for Read Operations

```ruby
# ✅ Good: Cached reads
class Product::IndexService < BetterService::IndexService
  cache_contexts :products
end

# ✅ Also good: Invalidate on writes
class Product::CreateService < BetterService::CreateService
  cache_contexts :products

  process_with do |data|
    product = model_class.create!(params)
    invalidate_cache_for(user)
    { resource: product }
  end
end
```

### 4. Use Presenters for Consistent Output

```ruby
# ✅ Good: Formatted output
class Product::ShowService < BetterService::ShowService
  presenter ProductPresenter
end

# Returns consistent format across all endpoints
```

### 5. Set Appropriate Transaction Levels

```ruby
# ✅ Good: Transaction for writes
class Order::CreateService < BetterService::CreateService
  self._transactional = true  # Default
end

# ✅ Good: No transaction for reads
class Report::GenerateService < BetterService::ActionService
  self._transactional = false
end
```

---

**See also:**
- [Services Structure](01_services_structure.md)
- [Cache Invalidation](../advanced/cache-invalidation.md)
- [Error Handling](../advanced/error-handling.md)
- [Testing](../testing.md)
