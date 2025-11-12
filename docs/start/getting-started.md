# Getting Started with BetterService

Welcome to BetterService! This guide will help you get up and running with BetterService in your Rails application.

## Table of Contents

- [Installation](#installation)
- [Initial Setup](#initial-setup)
- [Core Concepts](#core-concepts)
- [Your First Service](#your-first-service)
- [Understanding the 5-Phase Flow](#understanding-the-5-phase-flow)
- [Using Generators](#using-generators)
- [Next Steps](#next-steps)

---

## Installation

### Step 1: Add the Gem

Add BetterService to your `Gemfile`:

```ruby
gem "better_service"
```

Then run:

```bash
bundle install
```

### Step 2: Generate Configuration

Generate the BetterService initializer:

```bash
rails generate better_service:install
```

This creates `config/initializers/better_service.rb` with all configuration options.

### Step 3: Verify Installation

Open a Rails console and verify:

```bash
rails console
```

```ruby
BetterService::VERSION
# => "1.0.1" (or your installed version)
```

---

## Initial Setup

### Optional: Configure BetterService

Edit `config/initializers/better_service.rb` to enable features:

```ruby
BetterService.configure do |config|
  # Enable logging for development
  config.log_subscriber_enabled = Rails.env.development?
  config.log_subscriber_level = :info

  # Enable stats collection
  config.stats_subscriber_enabled = true

  # Enable instrumentation (recommended)
  config.instrumentation_enabled = true
end
```

See [Configuration Guide](configuration.md) for all options.

---

## Core Concepts

### What is a Service Object?

A **Service Object** encapsulates a single business operation. Instead of putting business logic in controllers or models, you create a dedicated service class.

**Benefits:**
- **Single Responsibility**: Each service does one thing well
- **Testable**: Easy to unit test in isolation
- **Reusable**: Call from controllers, jobs, rake tasks, console
- **Maintainable**: Business logic is organized and discoverable

### The BetterService Philosophy

BetterService enforces a structured approach to service objects:

1. **Schema Validation** - All inputs are validated (mandatory)
2. **Authorization** - User permissions checked before execution
3. **Structured Flow** - Consistent 5-phase execution
4. **Exception-Based** - Errors raise exceptions (no success flags)
5. **Composability** - Services compose via Workflows

---

## Your First Service

Let's create a service to create a blog post.

### Step 1: Generate the Service

```bash
rails generate serviceable:create Post
```

This creates:
- `app/services/post/create_service.rb`
- `test/services/post/create_service_test.rb`

### Step 2: Define the Schema

Open `app/services/post/create_service.rb`:

```ruby
class Post::CreateService < BetterService::Services::CreateService
  # 1. Define what parameters are required/optional
  schema do
    required(:title).filled(:string)
    required(:body).filled(:string)
    optional(:published).maybe(:bool)
  end

  # 2. Process phase - create the post
  process_with do |data|
    post = user.posts.create!(
      title: params[:title],
      body: params[:body],
      published: params[:published] || false
    )

    { resource: post }
  end
end
```

### Step 3: Use the Service

In your controller:

```ruby
class PostsController < ApplicationController
  def create
    result = Post::CreateService.new(current_user, params: post_params).call

    render json: result, status: :created

  rescue BetterService::Errors::Runtime::ValidationError => e
    render json: {
      error: "Validation failed",
      errors: e.context[:validation_errors]
    }, status: :unprocessable_entity

  rescue BetterService::Errors::Runtime::DatabaseError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def post_params
    params.require(:post).permit(:title, :body, :published)
  end
end
```

### Step 4: Test It

```bash
# In Rails console
user = User.first

# Valid params - succeeds
result = Post::CreateService.new(user, params: {
  title: "My First Post",
  body: "This is the content"
}).call

result[:success]    # => true
result[:resource]   # => <Post id: 1, title: "My First Post", ...>
result[:metadata]   # => { action: :created }

# Invalid params - raises exception
Post::CreateService.new(user, params: {
  title: "",  # Invalid: must be filled
  body: "Content"
})
# => BetterService::Errors::Runtime::ValidationError: Validation failed
```

---

## Understanding the 5-Phase Flow

Every BetterService execution follows these phases:

```
┌─────────────┐
│ 1. VALIDATE │  Validate params against schema (during initialize)
└──────┬──────┘
       │
┌──────▼────────┐
│ 2. AUTHORIZE  │  Check user permissions (optional)
└──────┬────────┘
       │
┌──────▼────────┐
│ 3. SEARCH     │  Load data from database/APIs
└──────┬────────┘
       │
┌──────▼────────┐
│ 4. PROCESS    │  Transform data, business logic
└──────┬────────┘
       │
┌──────▼────────┐
│ 5. RESPOND    │  Format final response
└───────────────┘
```

### Phase 1: Validation (Automatic)

**When**: During `initialize()` - before `.call()`
**Purpose**: Validate all input parameters
**Error**: Raises `ValidationError` if invalid

```ruby
schema do
  required(:email).filled(:string)
  required(:age).filled(:integer, gteq?: 18)
  optional(:newsletter).maybe(:bool)
end
```

### Phase 2: Authorization (Optional)

**When**: Start of `.call()`, before search
**Purpose**: Check if user can perform this action
**Error**: Raises `AuthorizationError` if unauthorized

```ruby
authorize_with do
  user.admin? || resource.user_id == user.id
end
```

### Phase 3: Search

**When**: After authorization
**Purpose**: Load data needed for processing

```ruby
search_with do
  { post: Post.find(params[:id]) }
end
```

### Phase 4: Process

**When**: After search
**Purpose**: Execute business logic, transform data

```ruby
process_with do |data|
  post = data[:post]
  post.update!(published: true, published_at: Time.current)

  { resource: post }
end
```

### Phase 5: Respond

**When**: After process
**Purpose**: Format the final response

```ruby
respond_with do |data|
  success_result("Post published successfully", data)
end
```

---

## Using Generators

BetterService provides 8 powerful generators:

### Generate All CRUD Services

```bash
rails generate serviceable:scaffold Product
```

Creates:
- `Product::IndexService` - List products
- `Product::ShowService` - Show single product
- `Product::CreateService` - Create product
- `Product::UpdateService` - Update product
- `Product::DestroyService` - Delete product

### Generate Individual Services

```bash
# Index service (list/collection)
rails generate serviceable:index Product

# Show service (single resource)
rails generate serviceable:show Product

# Create service
rails generate serviceable:create Product

# Update service
rails generate serviceable:update Product

# Destroy service
rails generate serviceable:destroy Product

# Custom action service
rails generate serviceable:action Product publish

# Workflow (compose multiple services)
rails generate serviceable:workflow OrderPurchase --steps create_order charge_payment
```

---

## Next Steps

### Learn More About Services

Explore the different service types:

- **[Service Types Overview](../services/01_services_structure.md)** - Understanding all 6 service types
- **[IndexService](../services/02_index_service.md)** - List and filter resources
- **[ShowService](../services/03_show_service.md)** - Retrieve single resources
- **[CreateService](../services/04_create_service.md)** - Create new resources
- **[UpdateService](../services/05_update_service.md)** - Modify existing resources
- **[DestroyService](../services/06_destroy_service.md)** - Delete resources
- **[ActionService](../services/07_action_service.md)** - Custom business actions

### Advanced Topics

- **[Configuration](configuration.md)** - Configure instrumentation, logging, stats
- **[Concerns Reference](../concerns-reference.md)** - Deep dive into all 7 concerns
- **[Workflows](../workflows/01_workflows_introduction.md)** - Compose multiple services
- **[Error Handling](../advanced/error-handling.md)** - Exception handling patterns
- **[Cache Management](../advanced/cache-invalidation.md)** - Caching strategies
- **[Testing](../testing.md)** - How to test your services

### Examples

- **[E-commerce Example](../examples/e-commerce.md)** - Complete e-commerce implementation

---

## Quick Reference

### Service Initialization

```ruby
service = ServiceClass.new(user, params: { ... })
result = service.call
```

### Success Response Structure

```ruby
{
  success: true,
  message: "Operation successful",
  resource: <Object>,  # or items: [...]
  metadata: {
    action: :created  # or :updated, :deleted, :show, :index
  }
}
```

### Error Handling

```ruby
begin
  result = MyService.new(user, params: params).call
  # Success - use result[:resource] or result[:items]
rescue BetterService::Errors::Runtime::ValidationError => e
  # Invalid params - e.context[:validation_errors]
rescue BetterService::Errors::Runtime::AuthorizationError => e
  # Not authorized - e.message
rescue BetterService::Errors::Runtime::ResourceNotFoundError => e
  # Record not found - e.message
rescue BetterService::Errors::Runtime::DatabaseError => e
  # DB constraint or validation - e.original_error
end
```

### Common Patterns

**Authorization by ownership:**
```ruby
authorize_with do
  resource.user_id == user.id || user.admin?
end
```

**Conditional logic:**
```ruby
process_with do |data|
  resource = data[:resource]

  if params[:publish]
    resource.publish!
  end

  { resource: resource }
end
```

**Cache invalidation:**
```ruby
process_with do |data|
  product = Product.create!(params)
  invalidate_cache_for(user)  # Invalidates configured cache contexts
  { resource: product }
end
```

---

## Need Help?

- **Issues**: [GitHub Issues](https://github.com/alessiobussolari/better_service/issues)
- **Documentation**: Check the `docs/` directory
- **Examples**: See `docs/examples/` for real-world patterns

---

**Next**: [Configuration Guide →](configuration.md)
