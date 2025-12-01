# API Reference

Complete DSL reference for BetterService with examples.

---

## Complete Service Example

### Full-Featured Service

A comprehensive service demonstrating all available DSL options.

```ruby
class Product::CreateService < BetterService::Services::Base
  include BetterService::Concerns::Serviceable::RepositoryAware
  include BetterService::Concerns::Serviceable::Cacheable
  include BetterService::Concerns::Serviceable::Presentable

  # ═══════════════════════════════════════════════════════════
  # CONFIGURATION DSL
  # ═══════════════════════════════════════════════════════════

  # I18n namespace for messages
  messages_namespace :products

  # Allow nil user (default: false)
  allow_nil_user false

  # Action name for metadata
  performed_action :created

  # Wrap in database transaction
  with_transaction true

  # ═══════════════════════════════════════════════════════════
  # REPOSITORY DSL
  # ═══════════════════════════════════════════════════════════

  # Single repository (creates product_repository helper)
  repository :product

  # Multiple repositories (shorthand)
  # repositories :product, :category, :tag

  # ═══════════════════════════════════════════════════════════
  # CACHE DSL
  # ═══════════════════════════════════════════════════════════

  # Cache key pattern
  cache_key ->(service) { "products:#{service.params[:id]}" }

  # Time-to-live for cache
  cache_ttl 1.hour

  # Contexts for cache invalidation
  cache_contexts [:products, :catalog]

  # Auto-invalidate on write operations (default: true for CUD)
  auto_invalidate_cache true

  # ═══════════════════════════════════════════════════════════
  # PRESENTER DSL
  # ═══════════════════════════════════════════════════════════

  # Presenter class for transformation
  presenter ProductPresenter

  # Options passed to presenter
  presenter_options ->(service) {
    { current_user: service.user, include_stats: true }
  }

  # ═══════════════════════════════════════════════════════════
  # VALIDATION DSL (Dry::Schema)
  # ═══════════════════════════════════════════════════════════

  schema do
    required(:name).filled(:string, min_size?: 2, max_size?: 100)
    required(:price).filled(:decimal, gt?: 0)
    required(:category_id).filled(:integer)
    optional(:description).filled(:string, max_size?: 5000)
    optional(:tags).array(:string)
    optional(:published).filled(:bool)
  end

  # ═══════════════════════════════════════════════════════════
  # AUTHORIZATION DSL
  # ═══════════════════════════════════════════════════════════

  authorize_with do
    # IMPORTANT: Use `next`, never `return`
    next true if user.admin?
    next true if user.seller?
    false
  end

  # ═══════════════════════════════════════════════════════════
  # PHASE DSL
  # ═══════════════════════════════════════════════════════════

  # Phase 3: Load data
  search_with do
    category = Category.find(params[:category_id])
    { category: category, user_products_count: user.products.count }
  end

  # Phase 4: Business logic
  process_with do |data|
    product = product_repository.create!(
      name: params[:name],
      price: params[:price],
      description: params[:description],
      category: data[:category],
      tags: params[:tags] || [],
      published: params[:published] || false,
      user: user
    )

    # Optionally invalidate specific caches manually
    invalidate_cache_for(:catalog)

    # Return resource for respond_with
    { resource: product, products_count: data[:user_products_count] + 1 }
  end

  # Alternative to presenter: transform_with
  # transform_with do |data|
  #   data[:resource].as_json(include: :category)
  # end

  # Phase 5: Format response
  respond_with do |data|
    success_result(
      message("create.success", name: data[:resource].name),
      data
    )
  end
end
```

--------------------------------

## DSL Reference Table

### Quick Reference

All available DSL methods organized by category.

| DSL Method | Category | Description |
|------------|----------|-------------|
| `schema` | Validation | Define parameter validation rules |
| `allow_nil_user` | Authorization | Allow service to run without user |
| `authorize_with` | Authorization | Define authorization logic |
| `messages_namespace` | Messages | Set I18n namespace |
| `performed_action` | Metadata | Set action name for metadata |
| `with_transaction` | Transaction | Enable database transaction |
| `search_with` | Phase 3 | Load data from database |
| `process_with` | Phase 4 | Execute business logic |
| `transform_with` | Presenter | Transform data (alternative to presenter) |
| `respond_with` | Phase 5 | Format response |
| `repository` | Repository | Declare single repository dependency |
| `repositories` | Repository | Declare multiple repositories |
| `presenter` | Presenter | Set presenter class |
| `presenter_options` | Presenter | Set presenter options |
| `cache_key` | Cache | Define cache key pattern |
| `cache_ttl` | Cache | Set cache time-to-live |
| `cache_contexts` | Cache | Define cache invalidation contexts |
| `auto_invalidate_cache` | Cache | Control auto cache invalidation |

--------------------------------

## Validation DSL

### schema

Define parameter validation using Dry::Schema. Validation runs during `initialize`, raising `ValidationError` if invalid.

```ruby
schema do
  # Required fields
  required(:name).filled(:string)
  required(:email).filled(:string, format?: /@/)
  required(:age).filled(:integer, gteq?: 18)

  # Optional fields
  optional(:phone).filled(:string)
  optional(:notes).maybe(:string)

  # Nested objects
  required(:address).hash do
    required(:street).filled(:string)
    required(:city).filled(:string)
    optional(:zip).filled(:string)
  end

  # Arrays
  required(:tags).array(:string)
  optional(:items).array(:hash) do
    required(:name).filled(:string)
    required(:quantity).filled(:integer, gt?: 0)
  end
end
```

--------------------------------

### Validation Predicates

Common predicates available in schema definitions.

```ruby
schema do
  # Type predicates
  required(:name).filled(:string)
  required(:count).filled(:integer)
  required(:price).filled(:decimal)
  required(:active).filled(:bool)
  required(:date).filled(:date)

  # Comparison predicates
  required(:age).filled(:integer, gt?: 0)       # greater than
  required(:age).filled(:integer, gteq?: 18)    # greater than or equal
  required(:age).filled(:integer, lt?: 100)     # less than
  required(:age).filled(:integer, lteq?: 65)    # less than or equal

  # Size predicates
  required(:name).filled(:string, min_size?: 2)
  required(:name).filled(:string, max_size?: 100)
  required(:name).filled(:string, size?: 2..100)

  # Format predicates
  required(:email).filled(:string, format?: /@/)
  required(:code).filled(:string, format?: /^[A-Z]{3}$/)

  # Inclusion predicates
  required(:status).filled(:string, included_in?: %w[active inactive])
  required(:role).filled(:string, excluded_from?: %w[banned])
end
```

--------------------------------

## Authorization DSL

### authorize_with

Define authorization logic. Runs during `call` phase, before search. CRITICAL: Use `next`, never `return`.

```ruby
# Simple role check
authorize_with do
  next true if user.admin?
  user.seller?
end

# Resource-based authorization
authorize_with do
  next true if user.admin?

  # Check admin BEFORE loading resource
  product = Product.find_by(id: params[:id])
  next false unless product

  product.user_id == user.id
end

# Multiple conditions
authorize_with do
  next true if user.admin?
  next true if user.moderator? && params[:action] != :destroy
  next true if user.id == params[:user_id]
  false
end
```

--------------------------------

### allow_nil_user

Allow service to run without a user. Default is `false`.

```ruby
class Public::ProductIndexService < BetterService::Services::Base
  # Allow anonymous access
  allow_nil_user true

  schema do
    optional(:category).filled(:string)
  end

  authorize_with do
    true  # Public access
  end

  search_with do
    { items: Product.published.to_a }
  end
end
```

--------------------------------

## Messages DSL

### messages_namespace

Set I18n namespace for `message()` helper. Messages follow a 3-level fallback chain.

```ruby
class Product::CreateService < Product::BaseService
  messages_namespace :products

  respond_with do |data|
    # Looks up: products.services.create.success
    # Fallback: better_service.services.default.create.success
    # Final:    Returns key if not found
    success_result(message("create.success", name: data[:resource].name), data)
  end
end
```

```yaml
# config/locales/products.en.yml
en:
  products:
    services:
      create:
        success: "Product '%{name}' created successfully"
      update:
        success: "Product updated"
      destroy:
        success: "Product deleted"
```

--------------------------------

## Metadata DSL

### performed_action

Set action name for metadata. Included in all success responses.

```ruby
class Product::CreateService < Product::BaseService
  performed_action :created
end

class Product::PublishService < Product::BaseService
  performed_action :published
end

# Result metadata includes action
result = Product::CreateService.new(user, params: params).call
result.meta[:action]  # => :created
```

--------------------------------

## Transaction DSL

### with_transaction

Wrap `process_with` in database transaction. Default: `true` for Create/Update/Destroy, `false` for Index/Show.

```ruby
class Product::CreateService < Product::BaseService
  # Enable transaction (default for CUD)
  with_transaction true

  process_with do |data|
    product = product_repository.create!(params)
    product.tags.create!(names: params[:tags])  # Rolls back on failure
    { resource: product }
  end
end

class Product::IndexService < Product::BaseService
  # Disable transaction (default for read operations)
  with_transaction false
end
```

--------------------------------

## Phase DSL

### search_with

Phase 3: Load data from database. Return a hash that's passed to `process_with`.

```ruby
search_with do
  product = product_repository.find(params[:id])
  category = Category.find(params[:category_id])
  related = product_repository.related_to(product).limit(5)

  {
    product: product,
    category: category,
    related_products: related.to_a
  }
end
```

--------------------------------

### process_with

Phase 4: Execute business logic. Receives data from `search_with`. Must return hash with `:resource` or `:items`.

```ruby
process_with do |data|
  # Access search_with results via data hash
  product = data[:product]
  category = data[:category]

  # Perform business logic
  product.update!(
    name: params[:name],
    category: category,
    updated_at: Time.current
  )

  # Return resource for respond_with
  { resource: product, previous_category: data[:category] }
end

# For collections
process_with do |data|
  items = data[:products].map do |product|
    product.calculate_stats
    product
  end

  { items: items, total: items.count }
end
```

--------------------------------

### transform_with

Transform data before response. Alternative to using a presenter class.

```ruby
class Product::ShowService < Product::BaseService
  # Option 1: transform_with block
  transform_with do |data|
    product = data[:resource]
    {
      id: product.id,
      name: product.name,
      price_formatted: "$#{product.price}",
      category_name: product.category.name,
      created_at: product.created_at.iso8601
    }
  end
end
```

--------------------------------

### respond_with

Phase 5: Format final response. Receives data from `process_with` (or `transform_with`).

```ruby
respond_with do |data|
  # Use success_result helper for consistent format
  success_result(message("show.success"), data)
end

# Custom response format
respond_with do |data|
  {
    success: true,
    product: data[:resource],
    related: data[:related_products],
    metadata: { action: :showed, cached: data[:from_cache] }
  }
end
```

--------------------------------

## Repository DSL

### repository

Declare a single repository dependency. Creates `#{name}_repository` helper method.

```ruby
class Product::CreateService < BetterService::Services::Base
  include BetterService::Concerns::Serviceable::RepositoryAware

  repository :product

  process_with do |data|
    # Automatically creates product_repository helper
    product = product_repository.create!(params)
    { resource: product }
  end
end
```

--------------------------------

### repositories

Declare multiple repository dependencies (shorthand).

```ruby
class Order::CreateService < BetterService::Services::Base
  include BetterService::Concerns::Serviceable::RepositoryAware

  # Declares all three repositories
  repositories :order, :product, :inventory

  process_with do |data|
    order = order_repository.create!(user: user, total: data[:total])

    data[:items].each do |item|
      product = product_repository.find(item[:product_id])
      inventory_repository.decrement!(product, item[:quantity])
      order.items.create!(product: product, quantity: item[:quantity])
    end

    { resource: order }
  end
end
```

--------------------------------

## Presenter DSL

### presenter

Set presenter class for data transformation.

```ruby
class ProductPresenter < BetterService::Presenter
  def as_json(options = {})
    {
      id: object.id,
      name: object.name,
      price: format_price(object.price),
      category: object.category.name,
      seller: current_user&.admin? ? object.user.email : nil
    }
  end

  private

  def format_price(price)
    "$#{'%.2f' % price}"
  end
end

class Product::ShowService < Product::BaseService
  presenter ProductPresenter
end
```

--------------------------------

### presenter_options

Set options passed to presenter. Can be a hash or lambda.

```ruby
class Product::ShowService < Product::BaseService
  presenter ProductPresenter

  # Static options
  presenter_options({ include_stats: true })

  # Dynamic options with lambda
  presenter_options ->(service) {
    {
      current_user: service.user,
      include_private: service.user&.admin?,
      locale: I18n.locale
    }
  }
end
```

--------------------------------

## Cache DSL

### cache_key

Define cache key pattern. Can be a string or lambda.

```ruby
class Product::ShowService < Product::BaseService
  include BetterService::Concerns::Serviceable::Cacheable

  # Static key
  cache_key "products:show"

  # Dynamic key with lambda
  cache_key ->(service) {
    "products:#{service.params[:id]}:#{service.user&.id}"
  }

  # With version
  cache_key ->(service) {
    product = Product.find(service.params[:id])
    "products:#{product.id}:v#{product.cache_version}"
  }
end
```

--------------------------------

### cache_ttl

Set cache time-to-live. Default is 1 hour.

```ruby
class Product::ShowService < Product::BaseService
  include BetterService::Concerns::Serviceable::Cacheable

  cache_key ->(s) { "products:#{s.params[:id]}" }

  # TTL options
  cache_ttl 30.minutes
  cache_ttl 1.hour
  cache_ttl 1.day
  cache_ttl 1.week
end
```

--------------------------------

### cache_contexts

Define contexts for cache invalidation grouping.

```ruby
class Product::BaseService < BetterService::Services::Base
  include BetterService::Concerns::Serviceable::Cacheable

  # Products invalidated together
  cache_contexts [:products]
end

class Catalog::IndexService < BetterService::Services::Base
  include BetterService::Concerns::Serviceable::Cacheable

  # Invalidated when products OR categories change
  cache_contexts [:products, :categories, :catalog]
end

# Manual invalidation
invalidate_cache_for(:products)  # Invalidates all :products context
invalidate_cache_for(:catalog)   # Invalidates all :catalog context
```

--------------------------------

### auto_invalidate_cache

Control automatic cache invalidation. Default: `true` for Create/Update/Destroy.

```ruby
class Product::CreateService < Product::BaseService
  # Auto-invalidate after successful create (default: true)
  auto_invalidate_cache true
end

class Product::BulkImportService < Product::BaseService
  # Disable for bulk operations, invalidate manually at end
  auto_invalidate_cache false

  process_with do |data|
    products = data[:items].map { |item| product_repository.create!(item) }

    # Single invalidation at end
    invalidate_cache_for(:products)
    invalidate_cache_for(:catalog)

    { items: products }
  end
end
```

--------------------------------

## Helper Methods

### user

Access the current user passed to the service.

```ruby
class Product::CreateService < Product::BaseService
  process_with do |data|
    product = product_repository.create!(
      name: params[:name],
      user: user,  # Current user
      created_by_admin: user.admin?
    )
    { resource: product }
  end
end
```

--------------------------------

### params

Access validated parameters. Only contains params that passed schema validation.

```ruby
class Product::UpdateService < Product::BaseService
  schema do
    required(:id).filled(:integer)
    optional(:name).filled(:string)
    optional(:price).filled(:decimal, gt?: 0)
  end

  process_with do |data|
    # params only includes validated fields
    # Invalid or extra fields are excluded
    data[:product].update!(params.except(:id))
    { resource: data[:product] }
  end
end
```

--------------------------------

### message

I18n message helper with fallback chain.

```ruby
class Product::CreateService < Product::BaseService
  messages_namespace :products

  respond_with do |data|
    # Interpolation support
    success_result(
      message("create.success", name: data[:resource].name),
      data
    )
  end
end

# Fallback chain:
# 1. products.services.create.success (custom namespace)
# 2. better_service.services.default.create.success (default)
# 3. "create.success" (key itself)
```

--------------------------------

### success_result

Build a standardized success response.

```ruby
respond_with do |data|
  # Basic usage
  success_result("Product created", data)

  # Returns:
  # {
  #   success: true,
  #   message: "Product created",
  #   metadata: { action: :created, success: true },
  #   resource: <Product>,
  #   ...data
  # }
end
```

--------------------------------

### failure_result

Build a standardized failure response (used internally).

```ruby
# Internal usage - failures are typically raised as exceptions
failure_result("Operation failed", error_code: :invalid_state)

# Returns:
# {
#   success: false,
#   message: "Operation failed",
#   metadata: { action: :created, success: false, error_code: :invalid_state }
# }
```

--------------------------------

### invalidate_cache_for

Manually invalidate cache for a specific context.

```ruby
class Product::UpdateService < Product::BaseService
  process_with do |data|
    product = data[:product]
    product.update!(params.except(:id))

    # Invalidate related caches
    invalidate_cache_for(:products)
    invalidate_cache_for(:catalog)

    # Invalidate specific user's cache
    if product.featured_changed?
      invalidate_cache_for(:homepage)
    end

    { resource: product }
  end
end
```

--------------------------------

## Result Object

### Result API

The Result wrapper returned by all services.

```ruby
result = Product::CreateService.new(user, params: params).call

# Boolean check
result.success?   # => true/false
result.failure?   # => true/false

# Access data
result.resource   # => The main object (Product)
result.message    # => "Product created successfully"
result.meta       # => { action: :created, success: true }
result.action     # => :created

# Destructuring support
resource, meta = result
product, meta = result

# Convert to hash/array
result.to_h       # => { resource: ..., meta: ... }
result.to_ary     # => [resource, meta]
```

--------------------------------

### Hash-like Interface

Access result data using Hash-like methods.

```ruby
result = Product::CreateService.new(user, params: params).call

# Bracket access []
result[:resource]     # => #<Product id: 1>
result[:meta]         # => { action: :created, success: true }
result[:success]      # => true
result[:message]      # => "Product created"
result[:action]       # => :created
result[:error_code]   # => :unauthorized (on failure)
result[:custom_key]   # => value from meta[:custom_key]

# Nested access with dig
result.dig(:resource)                           # => #<Product>
result.dig(:meta, :action)                      # => :created
result.dig(:validation_errors, :name)           # => ["can't be blank"]
result.dig(:nonexistent)                        # => nil (safe)

# Key existence check
result.key?(:resource)     # => true
result.key?(:meta)         # => true
result.key?(:success)      # => true
result.key?(:action)       # => true
result.key?(:unknown)      # => false
result.has_key?(:resource) # => true (alias)
```

--------------------------------

## Workflow DSL

### step

Define a workflow step with service, input mapping, and optional rollback.

```ruby
class Order::CheckoutWorkflow < BetterService::Workflows::Base
  step :validate_cart,
       with: Cart::ValidateService,
       input: ->(ctx) { { cart_id: ctx.cart_id } }

  step :charge_payment,
       with: Payment::ChargeService,
       input: ->(ctx) { { amount: ctx.validate_cart.total } },
       rollback: ->(ctx) {
         Payment::RefundService.new(ctx.user, params: {
           charge_id: ctx.charge_payment.id
         }).call
       }

  step :send_email,
       with: Email::ConfirmationService,
       input: ->(ctx) { { order: ctx.create_order } },
       optional: true  # Failure doesn't stop workflow
end
```

--------------------------------

### branch / on / otherwise

Conditional branching in workflows. Only one branch executes.

```ruby
class Payment::ProcessWorkflow < BetterService::Workflows::Base
  step :validate, with: Payment::ValidateService

  branch do
    on ->(ctx) { ctx.validate.method == :card } do
      step :charge_card, with: Payment::CardService
    end

    on ->(ctx) { ctx.validate.method == :paypal } do
      step :charge_paypal, with: Payment::PaypalService
    end

    on ->(ctx) { ctx.validate.method == :bank } do
      step :initiate_transfer, with: Payment::BankService
    end

    otherwise do
      step :manual_review, with: Payment::ManualService
    end
  end

  step :confirm, with: Payment::ConfirmService
end
```

--------------------------------

### Workflow Hooks

Lifecycle hooks for workflows.

```ruby
class Order::CheckoutWorkflow < BetterService::Workflows::Base
  before_workflow do |context|
    Rails.logger.info "Starting checkout for user #{context.user.id}"
  end

  after_workflow do |context, result|
    Rails.logger.info "Checkout completed: #{result[:success]}"
  end

  around_step do |step, context, &block|
    Rails.logger.info "Starting step: #{step[:name]}"
    result = block.call
    Rails.logger.info "Completed step: #{step[:name]}"
    result
  end

  step :validate, with: ValidateService
  step :process, with: ProcessService
end
```

--------------------------------

## Error Codes

### Exception Reference

All exceptions with their codes for programmatic handling.

| Exception | Code | When Raised |
|-----------|------|-------------|
| `ValidationError` | `:validation_failed` | Schema validation fails (during `initialize`) |
| `AuthorizationError` | `:unauthorized` | `authorize_with` returns false |
| `ResourceNotFoundError` | `:resource_not_found` | Record not found |
| `DatabaseError` | `:database_error` | Database operation fails |
| `TransactionError` | `:transaction_error` | Transaction rollback |
| `ExecutionError` | `:execution_error` | Unexpected runtime error |
| `SchemaRequiredError` | `:schema_required` | Missing schema definition |
| `NilUserError` | `:nil_user` | User is nil when required |

--------------------------------

