<div align="center">

# BetterService

### Clean, powerful Service Objects for Rails

[![Gem Version](https://badge.fury.io/rb/better_service.svg)](https://badge.fury.io/rb/better_service)
[![CI](https://github.com/alessiobussolari/better_service/actions/workflows/ci.yml/badge.svg)](https://github.com/alessiobussolari/better_service/actions/workflows/ci.yml)
[![Codecov](https://codecov.io/gh/alessiobussolari/better_service/branch/main/graph/badge.svg)](https://codecov.io/gh/alessiobussolari/better_service)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.0-ruby.svg)](https://www.ruby-lang.org/)
[![Rails](https://img.shields.io/badge/rails-%3E%3D%207.0-CC0000.svg)](https://rubyonrails.org/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[![Downloads](https://img.shields.io/gem/dt/better_service.svg)](https://rubygems.org/gems/better_service)
[![Documentation](https://img.shields.io/badge/docs-rubydoc.info-blue.svg)](https://rubydoc.info/gems/better_service)
[![GitHub issues](https://img.shields.io/github/issues/alessiobussolari/better_service.svg)](https://github.com/alessiobussolari/better_service/issues)
[![GitHub stars](https://img.shields.io/github/stars/alessiobussolari/better_service.svg)](https://github.com/alessiobussolari/better_service/stargazers)
[![Contributors](https://img.shields.io/github/contributors/alessiobussolari/better_service.svg)](https://github.com/alessiobussolari/better_service/graphs/contributors)

[Features](#-features) • [Installation](#-installation) • [Quick Start](#-quick-start) • [Documentation](#-documentation) • [Usage](#-usage) • [Error Handling](#%EF%B8%8F-error-handling) • [Examples](#-examples)

</div>

---

## ✨ Features

BetterService is a comprehensive Service Objects framework for Rails that brings clean architecture and powerful features to your business logic layer.

**Version 2.1.0** • 1,000+ tests passing (812 gem + 275 rails_app)

### Core Features

- 🎯 **4-Phase Flow Architecture**: Structured flow with validation → authorization → search → process → respond
- 📦 **Result Wrapper**: `BetterService::Result` with `.success?`, `.resource`, `.meta`, `.message` and destructuring support
- 🏛️ **Repository Pattern**: Clean data access with `RepositoryAware` concern and `repository :model_name` DSL
- ✅ **Mandatory Schema Validation**: Built-in [Dry::Schema](https://dry-rb.org/gems/dry-schema/) validation for all params
- 🔄 **Transaction Support**: Automatic database transaction wrapping with rollback
- 🔐 **Flexible Authorization**: `authorize_with` DSL that works with any auth system (Pundit, CanCanCan, custom)
- ⚠️ **Rich Error Handling**: Pure Exception Pattern with hierarchical errors, rich context, and detailed debugging info

### Advanced Features

- 💾 **Cache Management**: Built-in `CacheService` for invalidating cache by context, user, or globally with async support
- 🔄 **Auto-Invalidation**: Write operations (Create/Update/Destroy) automatically invalidate cache when configured
- 🌍 **I18n Support**: Built-in internationalization with `message()` helper, custom namespaces, and fallback chain
- 🎨 **Presenter System**: Optional data transformation layer with `BetterService::Presenter` base class
- 📊 **Metadata Tracking**: Automatic action metadata in all service responses
- 🔗 **Workflow Composition**: Chain multiple services into pipelines with conditional steps, rollback support, and lifecycle hooks
- 🌲 **Conditional Branching**: Multi-path workflow execution with `branch`/`on`/`otherwise` DSL for clean conditional logic
- 🏗️ **Powerful Generators**: 11 generators for rapid scaffolding (base, scaffold, CRUD services, action, workflow, locale, presenter)
- 🎨 **DSL-Based**: Clean, expressive DSL with `search_with`, `process_with`, `authorize_with`, etc.

---

## 📦 Installation

Add this line to your application's Gemfile:

```ruby
gem "better_service"
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install better_service
```

---

## 🚀 Quick Start

### 1. Generate Services

```bash
# Generate BaseService + Repository + locale file
rails generate serviceable:base Product

# Generate all CRUD services inheriting from BaseService
rails generate serviceable:scaffold Product --base

# Or generate individual services
rails generate serviceable:create Product --base_class=Product::BaseService
rails generate serviceable:action Product publish
```

### 2. Use the Service with Result Wrapper

```ruby
# Create a product
result = Product::CreateService.new(current_user, params: {
  name: "MacBook Pro",
  price: 2499.99
}).call

# Check success with Result wrapper
if result.success?
  product = result.resource   # => Product object
  message = result.message    # => "Product created successfully"
  action = result.meta[:action]  # => :created
else
  error_code = result.meta[:error_code]  # => :unauthorized
  message = result.message  # => "Not authorized"
end

# Or use destructuring
product, meta = result
redirect_to product if meta[:success]
```

---

## 📖 Documentation

Comprehensive guides and examples are available in the `/docs` directory:

### 🎓 Guides

- **[Getting Started](docs/start/getting-started.md)** - Installation, core concepts, your first service
- **[Service Types](docs/services/01_services_structure.md)** - Deep dive into all 6 service types (Index, Show, Create, Update, Destroy, Action)
- **[Concerns Reference](docs/concerns-reference.md)** - Complete reference for all 7 concerns (Validatable, Authorizable, Cacheable, etc.)

### 💡 Examples

- **[E-commerce](docs/examples/e-commerce.md)** - Complete e-commerce implementation (products, cart, checkout)

### 🔧 Configuration

See **[Configuration Guide](docs/start/configuration.md)** for all options including:
- Instrumentation & Observability
- Built-in LogSubscriber and StatsSubscriber
- Cache configuration

---

## 📚 Usage

### Service Architecture

All services inherit from `BetterService::Services::Base` via a resource-specific BaseService:

```ruby
# 1. BaseService with Repository (generated with `rails g serviceable:base Product`)
class Product::BaseService < BetterService::Services::Base
  include BetterService::Concerns::Serviceable::RepositoryAware

  messages_namespace :products
  cache_contexts [:products]
  repository :product  # Injects product_repository method
end

# 2. All services inherit from BaseService
class Product::CreateService < Product::BaseService
  performed_action :created
  with_transaction true
  auto_invalidate_cache true

  # Schema Validation (mandatory)
  schema do
    required(:name).filled(:string, min_size?: 2)
    required(:price).filled(:decimal, gt?: 0)
  end

  # Authorization - IMPORTANT: use `next` not `return`
  authorize_with do
    next true if user.admin?  # Admin bypass
    user.seller?
  end

  # Search Phase - Load data
  search_with do
    {}  # No data to load for create
  end

  # Process Phase - Business logic
  process_with do |_data|
    product = product_repository.create!(
      name: params[:name],
      price: params[:price],
      user: user
    )
    # IMPORTANT: Return { resource: ... } for proper extraction
    { resource: product }
  end

  # Respond Phase - Format response with Result wrapper
  respond_with do |data|
    success_result(message("create.success", name: data[:resource].name), data)
  end
end
```

### Available Service Types

#### 1. 📋 IndexService - List Resources

```ruby
class Product::IndexService < BetterService::Services::IndexService
  schema do
    optional(:page).filled(:integer, gteq?: 1)
    optional(:search).maybe(:string)
  end

  search_with do
    products = user.products
    products = products.where("name LIKE ?", "%#{params[:search]}%") if params[:search]
    { items: products.to_a }
  end

  process_with do |data|
    {
      items: data[:items],
      metadata: {
        total: data[:items].count,
        page: params[:page] || 1
      }
    }
  end
end

# Usage
result = Product::IndexService.new(current_user, params: { search: "MacBook" }).call
products = result[:items]  # => Array of products
```

#### 2. 👁️ ShowService - Show Single Resource

```ruby
class Product::ShowService < BetterService::Services::ShowService
  schema do
    required(:id).filled(:integer)
  end

  search_with do
    { resource: user.products.find(params[:id]) }
  end
end

# Usage
result = Product::ShowService.new(current_user, params: { id: 123 }).call
product = result[:resource]
```

#### 3. ➕ CreateService - Create Resource

```ruby
class Product::CreateService < BetterService::Services::CreateService
  # Transaction enabled by default ✅

  schema do
    required(:name).filled(:string)
    required(:price).filled(:decimal, gt?: 0)
  end

  process_with do |data|
    product = user.products.create!(params)
    { resource: product }
  end
end

# Usage
result = Product::CreateService.new(current_user, params: {
  name: "iPhone",
  price: 999
}).call
```

#### 4. ✏️ UpdateService - Update Resource

```ruby
class Product::UpdateService < BetterService::Services::UpdateService
  # Transaction enabled by default ✅

  schema do
    required(:id).filled(:integer)
    optional(:price).filled(:decimal, gt?: 0)
  end

  authorize_with do
    product = Product.find(params[:id])
    product.user_id == user.id
  end

  search_with do
    { resource: user.products.find(params[:id]) }
  end

  process_with do |data|
    product = data[:resource]
    product.update!(params.except(:id))
    { resource: product }
  end
end
```

#### 5. ❌ DestroyService - Delete Resource

```ruby
class Product::DestroyService < BetterService::Services::DestroyService
  # Transaction enabled by default ✅

  schema do
    required(:id).filled(:integer)
  end

  authorize_with do
    product = Product.find(params[:id])
    user.admin? || product.user_id == user.id
  end

  search_with do
    { resource: user.products.find(params[:id]) }
  end

  process_with do |data|
    data[:resource].destroy!
    { resource: data[:resource] }
  end
end
```

#### 6. ⚡ Custom Action Services

```ruby
class Product::PublishService < Product::BaseService
  # Action name for metadata
  performed_action :publish

  schema do
    required(:id).filled(:integer)
  end

  authorize_with do
    user.can_publish_products?
  end

  search_with do
    { resource: product_repository.find(params[:id]) }
  end

  process_with do |data|
    product = data[:resource]
    product.update!(published: true, published_at: Time.current)
    { resource: product }
  end
end

# Usage
result = Product::PublishService.new(current_user, params: { id: 123 }).call
# => { success: true, resource: <Product>, metadata: { action: :publish } }
```

---

## 🔐 Authorization

BetterService provides a flexible `authorize_with` DSL that works with **any** authorization system:

### Simple Role-Based Authorization

```ruby
class Product::CreateService < Product::BaseService
  authorize_with do
    # IMPORTANT: Use `next` not `return` (return causes LocalJumpError)
    next true if user.admin?
    user.seller?
  end
end
```

### Resource Ownership Check (Admin Bypass Pattern)

```ruby
class Product::UpdateService < Product::BaseService
  authorize_with do
    # Admin can update any product (even non-existent - will get "not found" error)
    next true if user.admin?

    # For non-admin, check resource ownership
    product = Product.find_by(id: params[:id])
    next false unless product  # Return unauthorized if product doesn't exist

    product.user_id == user.id
  end
end
```

### Pundit Integration

```ruby
class Product::UpdateService < BetterService::Services::UpdateService
  authorize_with do
    ProductPolicy.new(user, Product.find(params[:id])).update?
  end
end
```

### CanCanCan Integration

```ruby
class Product::DestroyService < BetterService::Services::DestroyService
  authorize_with do
    Ability.new(user).can?(:destroy, :product)
  end
end
```

### Authorization Failure

When authorization fails, the service returns:

```ruby
{
  success: false,
  errors: ["Not authorized to perform this action"],
  code: :unauthorized
}
```

---

## 🔄 Transaction Support

Create, Update, and Destroy services have **automatic transaction support** enabled by default:

```ruby
class Product::CreateService < BetterService::Services::CreateService
  # Transactions enabled by default ✅

  process_with do |data|
    product = user.products.create!(params)

    # If anything fails here, the entire transaction rolls back
    ProductHistory.create!(product: product, action: "created")
    NotificationService.notify_admins(product)

    { resource: product }
  end
end
```

### Disable Transactions

```ruby
class Product::CreateService < BetterService::Services::CreateService
  with_transaction false  # Disable transactions

  # ...
end
```

---

## 📊 Metadata

All services automatically include metadata with the action name:

```ruby
result = Product::CreateService.new(user, params: { name: "Test" }).call

result[:metadata]
# => { action: :created }

result = Product::UpdateService.new(user, params: { id: 1, name: "Updated" }).call

result[:metadata]
# => { action: :updated }

result = Product::PublishService.new(user, params: { id: 1 }).call

result[:metadata]
# => { action: :publish }
```

You can add custom metadata in the `process_with` block:

```ruby
process_with do |data|
  {
    resource: product,
    metadata: {
      custom_field: "value",
      processed_at: Time.current
    }
  }
end
```

---

## ⚠️ Error Handling

BetterService uses a **Pure Exception Pattern** where all errors raise exceptions with rich context information. This ensures consistent behavior across all environments (development, test, production).

### Exception Hierarchy

```
BetterServiceError (base class)
├── Configuration Errors (programming errors)
│   ├── SchemaRequiredError - Missing schema definition
│   ├── InvalidSchemaError - Invalid schema syntax
│   ├── InvalidConfigurationError - Invalid config settings
│   └── NilUserError - User is nil when required
│
├── Runtime Errors (execution errors)
│   ├── ValidationError - Parameter validation failed
│   ├── AuthorizationError - User not authorized
│   ├── ResourceNotFoundError - Record not found
│   ├── DatabaseError - Database operation failed
│   ├── TransactionError - Transaction rollback
│   └── ExecutionError - Unexpected error
│
└── Workflowable Errors (workflow errors)
    ├── Configuration
    │   ├── WorkflowConfigurationError - Invalid workflow config
    │   ├── StepNotFoundError - Step not found
    │   ├── InvalidStepError - Invalid step definition
    │   └── DuplicateStepError - Duplicate step name
    └── Runtime
        ├── WorkflowExecutionError - Workflow execution failed
        ├── StepExecutionError - Step failed
        └── RollbackError - Rollback failed
```

### Handling Errors

#### 1. Validation Errors

Validation errors are raised during service **initialization** (not in `call`):

```ruby
begin
  service = Product::CreateService.new(current_user, params: {
    name: "",  # Invalid
    price: -10  # Invalid
  })
rescue BetterService::Errors::Runtime::ValidationError => e
  e.message  # => "Validation failed"
  e.code     # => :validation_failed

  # Access validation errors from context
  e.context[:validation_errors]
  # => {
  #   name: ["must be filled"],
  #   price: ["must be greater than 0"]
  # }

  # Render in controller
  render json: {
    error: e.message,
    errors: e.context[:validation_errors]
  }, status: :unprocessable_entity
end
```

#### 2. Authorization Errors

Authorization errors are raised during `call`:

```ruby
begin
  Product::DestroyService.new(current_user, params: { id: 1 }).call
rescue BetterService::Errors::Runtime::AuthorizationError => e
  e.message  # => "Not authorized to perform this action"
  e.code     # => :unauthorized
  e.context[:service]  # => "Product::DestroyService"
  e.context[:user]     # => user_id or "nil"

  # Render in controller
  render json: { error: e.message }, status: :forbidden
end
```

#### 3. Resource Not Found Errors

Raised when ActiveRecord records are not found:

```ruby
begin
  Product::ShowService.new(current_user, params: { id: 99999 }).call
rescue BetterService::Errors::Runtime::ResourceNotFoundError => e
  e.message  # => "Resource not found: Couldn't find Product..."
  e.code     # => :resource_not_found
  e.original_error  # => ActiveRecord::RecordNotFound instance

  # Render in controller
  render json: { error: "Product not found" }, status: :not_found
end
```

#### 4. Database Errors

Raised for database constraint violations and record invalid errors:

```ruby
begin
  Product::CreateService.new(current_user, params: {
    name: "Duplicate",  # Unique constraint violation
    sku: "INVALID"
  }).call
rescue BetterService::Errors::Runtime::DatabaseError => e
  e.message  # => "Database error: Validation failed..."
  e.code     # => :database_error
  e.original_error  # => ActiveRecord::RecordInvalid instance

  # Render in controller
  render json: { error: e.message }, status: :unprocessable_entity
end
```

#### 5. Workflow Errors

Workflows raise specific errors for step and rollback failures:

```ruby
begin
  OrderPurchaseWorkflow.new(current_user, params: params).call
rescue BetterService::Errors::Workflowable::Runtime::StepExecutionError => e
  e.message  # => "Step charge_payment failed: Payment declined"
  e.code     # => :step_failed
  e.context[:workflow]        # => "OrderPurchaseWorkflow"
  e.context[:step]            # => :charge_payment
  e.context[:steps_executed]  # => [:create_order]

rescue BetterService::Errors::Workflowable::Runtime::RollbackError => e
  e.message  # => "Rollback failed for step charge_payment: Refund failed"
  e.code     # => :rollback_failed
  e.context[:executed_steps]  # => [:create_order, :charge_payment]
  # ⚠️ Rollback errors indicate potential data inconsistency
end
```

### Error Information

All `BetterServiceError` exceptions provide rich debugging information:

```ruby
begin
  service.call
rescue BetterService::BetterServiceError => e
  # Basic info
  e.message        # Human-readable error message
  e.code           # Symbol code for programmatic handling
  e.timestamp      # When the error occurred

  # Context info
  e.context        # Hash with service-specific context
  # => { service: "MyService", params: {...}, validation_errors: {...} }

  # Original error (if wrapping another exception)
  e.original_error  # The original exception that was caught

  # Structured hash for logging
  e.to_h
  # => {
  #   error_class: "BetterService::Errors::Runtime::ValidationError",
  #   message: "Validation failed",
  #   code: :validation_failed,
  #   timestamp: "2025-11-09T10:30:00Z",
  #   context: { service: "MyService", validation_errors: {...} },
  #   original_error: { class: "StandardError", message: "...", backtrace: [...] },
  #   backtrace: [...]
  # }

  # Detailed message with all context
  e.detailed_message
  # => "Validation failed | Code: validation_failed | Context: {...} | Original: ..."

  # Enhanced backtrace (includes original error backtrace)
  e.backtrace
  # => ["...", "--- Original Error Backtrace ---", "..."]
end
```

### Controller Pattern

Recommended pattern for handling errors in controllers:

```ruby
class ProductsController < ApplicationController
  def create
    result = Product::CreateService.new(current_user, params: product_params).call
    render json: result, status: :created

  rescue BetterService::Errors::Runtime::ValidationError => e
    render json: {
      error: e.message,
      errors: e.context[:validation_errors]
    }, status: :unprocessable_entity

  rescue BetterService::Errors::Runtime::AuthorizationError => e
    render json: { error: e.message }, status: :forbidden

  rescue BetterService::Errors::Runtime::ResourceNotFoundError => e
    render json: { error: "Resource not found" }, status: :not_found

  rescue BetterService::Errors::Runtime::DatabaseError => e
    render json: { error: e.message }, status: :unprocessable_entity

  rescue BetterService::BetterServiceError => e
    # Catch-all for other service errors
    Rails.logger.error("Service error: #{e.to_h}")
    render json: { error: "An error occurred" }, status: :internal_server_error
  end
end
```

Or use a centralized error handler:

```ruby
class ApplicationController < ActionController::API
  rescue_from BetterService::Errors::Runtime::ValidationError do |e|
    render json: {
      error: e.message,
      errors: e.context[:validation_errors]
    }, status: :unprocessable_entity
  end

  rescue_from BetterService::Errors::Runtime::AuthorizationError do |e|
    render json: { error: e.message }, status: :forbidden
  end

  rescue_from BetterService::Errors::Runtime::ResourceNotFoundError do |e|
    render json: { error: "Resource not found" }, status: :not_found
  end

  rescue_from BetterService::Errors::Runtime::DatabaseError do |e|
    render json: { error: e.message }, status: :unprocessable_entity
  end

  rescue_from BetterService::BetterServiceError do |e|
    Rails.logger.error("Service error: #{e.to_h}")
    render json: { error: "An error occurred" }, status: :internal_server_error
  end
end
```

---

## 💾 Cache Management

BetterService provides built-in cache management through the `BetterService::CacheService` module, which works seamlessly with services that use the `Cacheable` concern.

### Cache Invalidation

The CacheService provides several methods for cache invalidation:

#### Invalidate for Specific User and Context

```ruby
# Invalidate cache for a specific user and context
BetterService::CacheService.invalidate_for_context(current_user, "products")
# Deletes all cache keys like: products_index:user_123:*:products

# Invalidate asynchronously (requires ActiveJob)
BetterService::CacheService.invalidate_for_context(current_user, "products", async: true)
```

#### Invalidate Globally for a Context

```ruby
# Invalidate cache for all users in a specific context
BetterService::CacheService.invalidate_global("sidebar")
# Deletes all cache keys matching: *:sidebar

# Useful after updating global settings that affect all users
BetterService::CacheService.invalidate_global("navigation", async: true)
```

#### Invalidate All Cache for a User

```ruby
# Invalidate all cached data for a specific user
BetterService::CacheService.invalidate_for_user(current_user)
# Deletes all cache keys matching: *:user_123:*

# Useful when user permissions or roles change
BetterService::CacheService.invalidate_for_user(user, async: true)
```

#### Invalidate Specific Key

```ruby
# Delete a single cache key
BetterService::CacheService.invalidate_key("products_index:user_123:abc:products")
```

#### Clear All BetterService Cache

```ruby
# WARNING: Clears ALL BetterService cache
# Use with caution, preferably only in development/testing
BetterService::CacheService.clear_all
```

### Cache Utilities

#### Fetch with Caching

```ruby
# Wrapper around Rails.cache.fetch
result = BetterService::CacheService.fetch("my_key", expires_in: 1.hour) do
  expensive_computation
end
```

#### Check Cache Existence

```ruby
if BetterService::CacheService.exist?("my_key")
  # Key exists in cache
end
```

#### Get Cache Statistics

```ruby
stats = BetterService::CacheService.stats
# => {
#   cache_store: "ActiveSupport::Cache::RedisStore",
#   supports_pattern_deletion: true,
#   supports_async: true
# }
```

### Integration with Services

The CacheService automatically works with services using the `Cacheable` concern:

```ruby
class Product::IndexService < BetterService::IndexService
  cache_key "products_index"
  cache_ttl 1.hour
  cache_contexts "products", "sidebar"

  # Service implementation...
end

# After creating a product, invalidate the cache
Product.create!(name: "New Product")
BetterService::CacheService.invalidate_for_context(current_user, "products")

# Or invalidate globally for all users
BetterService::CacheService.invalidate_global("products")
```

### Use Cases

#### After Model Updates

```ruby
class Product < ApplicationRecord
  after_commit :invalidate_product_cache, on: [ :create, :update, :destroy ]

  private

  def invalidate_product_cache
    # Invalidate for all users
    BetterService::CacheService.invalidate_global("products")
  end
end
```

#### After User Permission Changes

```ruby
class User < ApplicationRecord
  after_update :invalidate_user_cache, if: :saved_change_to_role?

  private

  def invalidate_user_cache
    # Invalidate all cache for this user
    BetterService::CacheService.invalidate_for_user(self)
  end
end
```

#### In Controllers

```ruby
class ProductsController < ApplicationController
  def create
    @product = Product.create!(product_params)

    # Invalidate cache for the current user
    BetterService::CacheService.invalidate_for_context(current_user, "products")

    redirect_to @product
  end
end
```

### Async Cache Invalidation

For better performance, use async invalidation with ActiveJob:

```ruby
# Queues a background job to invalidate cache
BetterService::CacheService.invalidate_for_context(
  current_user,
  "products",
  async: true
)
```

**Note**: Async invalidation requires ActiveJob to be configured in your Rails application.

### Cache Store Compatibility

The CacheService works with any Rails cache store, but pattern-based deletion (`delete_matched`) requires:
- MemoryStore ✅
- RedisStore ✅
- RedisCacheStore ✅
- MemCachedStore ⚠️ (limited support)
- NullStore ⚠️ (no-op)
- FileStore ⚠️ (limited support)

---

## 🔄 Auto-Invalidation Cache

Write operations (Create/Update/Destroy) can automatically invalidate cache after successful execution.

### How It Works

Auto-invalidation is **enabled by default** for Create, Update, and Destroy services when cache contexts are defined:

```ruby
class Products::CreateService < BetterService::Services::CreateService
  cache_contexts :products, :homepage

  # Cache is automatically invalidated for these contexts after create!
  # No need to call invalidate_cache_for manually
end
```

When the service completes successfully:
1. The product is created/updated/deleted
2. Cache is automatically invalidated for all defined contexts
3. All cache keys matching the patterns are cleared

### Disabling Auto-Invalidation

Control auto-invalidation with the `auto_invalidate_cache` DSL:

```ruby
class Products::CreateService < BetterService::Services::CreateService
  cache_contexts :products
  auto_invalidate_cache false  # Disable automatic invalidation

  process_with do |data|
    product = user.products.create!(params)

    # Manual control: only invalidate for featured products
    invalidate_cache_for(user) if product.featured?

    { resource: product }
  end
end
```

### Async Invalidation

Combine with async option for non-blocking cache invalidation:

```ruby
class Products::CreateService < BetterService::Services::CreateService
  cache_contexts :products, :homepage

  # Auto-invalidation happens async via ActiveJob
  cache_async true
end
```

**Note**: Auto-invalidation only applies to Create, Update, and Destroy services. Index and Show services don't trigger cache invalidation since they're read-only operations.

---

## 🌍 Internationalization (I18n)

BetterService includes built-in I18n support for service messages with automatic fallback.

### Using the message() Helper

All service templates use the `message()` helper for response messages:

```ruby
class Products::CreateService < BetterService::Services::CreateService
  respond_with do |data|
    success_result(message("create.success"), data)
  end
end
```

### Default Messages

BetterService ships with English defaults in `config/locales/better_service.en.yml`:

```yaml
en:
  better_service:
    services:
      default:
        created: "Resource created successfully"
        updated: "Resource updated successfully"
        deleted: "Resource deleted successfully"
        listed: "Resources retrieved successfully"
        shown: "Resource retrieved successfully"
```

### Custom Messages

Generate custom locale files for your services:

```bash
rails generate better_service:locale products
```

This creates `config/locales/products_services.en.yml`:

```yaml
en:
  products:
    services:
      create:
        success: "Product created and added to inventory"
      update:
        success: "Product updated successfully"
      destroy:
        success: "Product removed from catalog"
```

Then configure the namespace in your service:

```ruby
class Products::CreateService < BetterService::Services::CreateService
  messages_namespace :products

  respond_with do |data|
    # Uses products.services.create.success
    success_result(message("create.success"), data)
  end
end
```

### Fallback Chain

Messages follow a 3-level fallback:
1. Custom namespace (e.g., `products.services.create.success`)
2. BetterService defaults (e.g., `better_service.services.default.created`)
3. Key itself (e.g., `"create.success"`)

### Message Interpolations

Pass dynamic values to messages:

```ruby
respond_with do |data|
  success_result(
    message("create.success", product_name: data[:resource].name),
    data
  )
end
```

**Locale file:**
```yaml
en:
  products:
    services:
      create:
        success: "Product '%{product_name}' created successfully"
```

---

## 🎨 Presenter System

BetterService includes an optional presenter layer for formatting data for API/view consumption.

### Creating Presenters

Generate a presenter class:

```bash
rails generate better_service:presenter Product
```

This creates:
- `app/presenters/product_presenter.rb`
- `test/presenters/product_presenter_test.rb`

```ruby
class ProductPresenter < BetterService::Presenter
  def as_json(opts = {})
    {
      id: object.id,
      name: object.name,
      price: object.price,
      display_name: "#{object.name} - $#{object.price}",

      # Conditional fields based on user permissions
      **(admin_fields if current_user&.admin?)
    }
  end

  private

  def admin_fields
    {
      cost: object.cost,
      margin: object.price - object.cost
    }
  end
end
```

### Using Presenters in Services

Configure presenters via the `presenter` DSL:

```ruby
class Products::IndexService < BetterService::Services::IndexService
  presenter ProductPresenter

  presenter_options do
    { current_user: user }
  end

  # Items are automatically formatted via ProductPresenter#as_json
end
```

### Presenter Features

**Available Methods:**
- `object` - The resource being presented
- `options` - Options hash passed via `presenter_options`
- `current_user` - Shortcut for `options[:current_user]`
- `as_json(opts)` - Format object as JSON
- `to_json(opts)` - Serialize to JSON string
- `to_h` - Alias for `as_json`

**Example with scaffold:**
```bash
# Generate services + presenter in one command
rails generate serviceable:scaffold Product --presenter
```

---

## 🏗️ Generators

BetterService includes 10 powerful generators:

### Scaffold Generator

Generates all 5 CRUD services at once:

```bash
rails generate serviceable:scaffold Product

# With presenter
rails generate serviceable:scaffold Product --presenter
```

Creates:
- `app/services/product/index_service.rb`
- `app/services/product/show_service.rb`
- `app/services/product/create_service.rb`
- `app/services/product/update_service.rb`
- `app/services/product/destroy_service.rb`
- (Optional) `app/presenters/product_presenter.rb` with `--presenter`

### Individual Generators

```bash
# CRUD Services
rails generate serviceable:index Product
rails generate serviceable:show Product
rails generate serviceable:create Product
rails generate serviceable:update Product
rails generate serviceable:destroy Product

# Custom action service
rails generate serviceable:action Product publish

# Workflow for composing services
rails generate serviceable:workflow OrderPurchase --steps create_order charge_payment

# Presenter for data transformation
rails generate better_service:presenter Product

# Custom locale file for I18n messages
rails generate better_service:locale products
```

---

## 🎯 Examples

### Complete CRUD Workflow

```ruby
# 1. List products
index_result = Product::IndexService.new(current_user, params: {
  search: "MacBook",
  page: 1
}).call

products = index_result[:items]

# 2. Show a product
show_result = Product::ShowService.new(current_user, params: {
  id: products.first.id
}).call

product = show_result[:resource]

# 3. Create a new product
create_result = Product::CreateService.new(current_user, params: {
  name: "New Product",
  price: 99.99
}).call

new_product = create_result[:resource]

# 4. Update the product
update_result = Product::UpdateService.new(current_user, params: {
  id: new_product.id,
  price: 149.99
}).call

# 5. Publish the product (custom action)
publish_result = Product::PublishService.new(current_user, params: {
  id: new_product.id
}).call

# 6. Delete the product
destroy_result = Product::DestroyService.new(current_user, params: {
  id: new_product.id
}).call
```

### Controller Integration

```ruby
class ProductsController < ApplicationController
  def create
    result = Product::CreateService.new(current_user, params: product_params).call

    if result[:success]
      render json: {
        product: result[:resource],
        message: result[:message],
        metadata: result[:metadata]
      }, status: :created
    else
      render json: {
        errors: result[:errors]
      }, status: :unprocessable_entity
    end
  end

  private

  def product_params
    params.require(:product).permit(:name, :price, :description)
  end
end
```

---

## 🔗 Workflows - Service Composition

Workflows allow you to compose multiple services into a pipeline with explicit data mapping, conditional execution, automatic rollback, and lifecycle hooks.

### Creating a Workflow

Generate a workflow with the generator:

```bash
rails generate serviceable:workflow OrderPurchase --steps create_order charge_payment send_email
```

This creates `app/workflows/order_purchase_workflow.rb`:

```ruby
class OrderPurchaseWorkflow < BetterService::Workflow
  # Enable database transactions for the entire workflow
  with_transaction true

  # Lifecycle hooks
  before_workflow :validate_cart
  after_workflow :clear_cart
  around_step :log_step

  # Step 1: Create order
  step :create_order,
       with: Order::CreateService,
       input: ->(ctx) { { items: ctx.cart_items, total: ctx.total } }

  # Step 2: Charge payment with rollback
  step :charge_payment,
       with: Payment::ChargeService,
       input: ->(ctx) { { amount: ctx.order.total } },
       rollback: ->(ctx) { Payment::RefundService.new(ctx.user, params: { charge_id: ctx.charge.id }).call }

  # Step 3: Send email (optional, won't stop workflow if fails)
  step :send_email,
       with: Email::ConfirmationService,
       input: ->(ctx) { { order_id: ctx.order.id } },
       optional: true,
       if: ->(ctx) { ctx.user.notifications_enabled? }

  private

  def validate_cart(context)
    context.fail!("Cart is empty") if context.cart_items.empty?
  end

  def clear_cart(context)
    context.user.clear_cart! if context.success?
  end

  def log_step(step, context)
    Rails.logger.info "Executing: #{step.name}"
    yield
    Rails.logger.info "Completed: #{step.name}"
  end
end
```

### Using a Workflow

```ruby
# In your controller
result = OrderPurchaseWorkflow.new(current_user, params: {
  cart_items: [...],
  payment_method: "card_123"
}).call

if result[:success]
  # Access context data
  order = result[:context].order
  charge = result[:context].charge_payment

  render json: {
    order: order,
    metadata: result[:metadata]
  }, status: :created
else
  render json: {
    errors: result[:errors],
    failed_at: result[:metadata][:failed_step]
  }, status: :unprocessable_entity
end
```

### Workflow Features

#### 1. **Explicit Input Mapping**

Each step defines how data flows from the context to the service:

```ruby
step :charge_payment,
     with: Payment::ChargeService,
     input: ->(ctx) {
       {
         amount: ctx.order.total,
         currency: ctx.order.currency,
         payment_method: ctx.payment_method
       }
     }
```

#### 2. **Conditional Steps**

Steps can execute conditionally:

```ruby
step :send_sms,
     with: SMS::NotificationService,
     input: ->(ctx) { { order_id: ctx.order.id } },
     if: ->(ctx) { ctx.user.sms_enabled? && ctx.order.total > 100 }
```

#### 3. **Optional Steps**

Optional steps won't stop the workflow if they fail:

```ruby
step :update_analytics,
     with: Analytics::TrackService,
     input: ->(ctx) { { event: 'order_created', order_id: ctx.order.id } },
     optional: true  # Won't fail workflow if analytics service is down
```

#### 4. **Automatic Rollback**

Define rollback logic for each step:

```ruby
step :charge_payment,
     with: Payment::ChargeService,
     input: ->(ctx) { { amount: ctx.order.total } },
     rollback: ->(ctx) {
       # Automatically called if a later step fails
       Stripe::Refund.create(charge: ctx.charge_payment.id)
     }
```

When a step fails, all previously executed steps' rollback blocks are called in reverse order.

#### 5. **Transaction Support**

Wrap the entire workflow in a database transaction:

```ruby
class MyWorkflow < BetterService::Workflow
  with_transaction true  # DB changes are rolled back if workflow fails
end
```

#### 6. **Lifecycle Hooks**

**before_workflow**: Runs before any step executes

```ruby
before_workflow :validate_prerequisites

def validate_prerequisites(context)
  context.fail!("User not verified") unless context.user.verified?
end
```

**after_workflow**: Runs after all steps complete (success or failure)

```ruby
after_workflow :log_completion

def log_completion(context)
  Rails.logger.info "Workflow completed: success=#{context.success?}"
end
```

**around_step**: Wraps each step execution

```ruby
around_step :measure_performance

def measure_performance(step, context)
  start = Time.current
  yield  # Execute the step
  duration = Time.current - start
  Rails.logger.info "Step #{step.name}: #{duration}s"
end
```

### Workflow Response

Workflows return a standardized response:

```ruby
{
  success: true/false,
  message: "Workflow completed successfully",
  context: <Context object with all data>,
  metadata: {
    workflow: "OrderPurchaseWorkflow",
    steps_executed: [:create_order, :charge_payment, :send_email],
    steps_skipped: [],
    failed_step: nil,  # :step_name if failed
    duration_ms: 245.67
  }
}
```

### Context Object

The context object stores all workflow data and is accessible across all steps:

```ruby
# Set data
context.order = Order.create!(...)
context.add(:custom_key, value)

# Get data
order = context.order
value = context.get(:custom_key)

# Check status
context.success?  # => true
context.failure?  # => false

# Fail manually
context.fail!("Custom error message", field: "error detail")
```

### Generator Options

```bash
# Basic workflow
rails generate serviceable:workflow OrderPurchase

# With steps
rails generate serviceable:workflow OrderPurchase --steps create charge notify

# With transaction enabled
rails generate serviceable:workflow OrderPurchase --transaction

# Skip test file
rails generate serviceable:workflow OrderPurchase --skip-test
```

---

## 🧪 Testing

BetterService includes comprehensive test coverage. Run tests with:

```bash
# Run all tests
bundle exec rake

# Or
bundle exec rspec
```

### Manual Testing

A manual test script is included for hands-on verification:

```bash
cd spec/rails_app
rails console
load '../../manual_test.rb'
```

This runs 8 comprehensive tests covering all service types with automatic database rollback.

---

## 🤝 Contributing

Contributions are welcome! Here's how you can help:

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

Please make sure to:
- Add tests for new features
- Update documentation
- Follow the existing code style

---

## 🎉 Recent Features

### Observability & Instrumentation ✨

BetterService now includes comprehensive instrumentation powered by ActiveSupport::Notifications:

- **Automatic Event Publishing**: `service.started`, `service.completed`, `service.failed`, `cache.hit`, `cache.miss`
- **Built-in Subscribers**: LogSubscriber and StatsSubscriber for monitoring
- **Easy Integration**: DataDog, New Relic, Grafana, and custom subscribers
- **Zero Configuration**: Works out of the box, fully configurable

```ruby
# Enable monitoring in config/initializers/better_service.rb
BetterService.configure do |config|
  config.instrumentation_enabled = true
  config.log_subscriber_enabled = true
  config.stats_subscriber_enabled = true
end

# Custom subscriber
ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
  DataDog.histogram("service.duration", payload[:duration])
end
```

See [Configuration Guide](docs/start/configuration.md) for more details.

---

## 📄 License

The gem is available as open source under the terms of the [WTFPL License](http://www.wtfpl.net/about/).

---

<div align="center">

**Made with ❤️ by [Alessio Bussolari](https://github.com/alessiobussolari)**

[Report Bug](https://github.com/alessiobussolari/better_service/issues) · [Request Feature](https://github.com/alessiobussolari/better_service/issues) · [Documentation](https://github.com/alessiobussolari/better_service)

</div>
