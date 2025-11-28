# Services Structure

## Overview

BetterService provides 6 specialized service types, each optimized for specific operations. All services follow a consistent 5-phase execution flow and share common configuration options while adding specific behaviors for their use cases.

## The 6 Service Types

| Type | Purpose | Action | Transaction | Return Key | Generator |
|------|---------|--------|-------------|------------|-----------|
| **IndexService** | List/Collection retrieval | `:index` | OFF | `items` | `rails g serviceable:index` |
| **ShowService** | Single resource retrieval | `:show` | OFF | `resource` | `rails g serviceable:show` |
| **CreateService** | Resource creation | `:created` | ON | `resource` | `rails g serviceable:create` |
| **UpdateService** | Resource modification | `:updated` | ON | `resource` | `rails g serviceable:update` |
| **DestroyService** | Resource deletion | `:deleted` | ON | `resource` | `rails g serviceable:destroy` |
| **ActionService** | Custom operations | custom | OFF | `resource` | `rails g serviceable:action` |

## 5-Phase Execution Flow

Every service execution follows these phases in order:

```
1. VALIDATION    → Validate params against schema (Dry::Schema)
2. AUTHORIZATION → Check user permissions (authorize_with block)
3. SEARCH        → Load data from database/external sources
4. PROCESS       → Transform, aggregate, business logic
5. TRANSFORM     → Apply presenter or custom transformation
6. RESPOND       → Format final response
```

### Phase Details

#### Phase 1: Validation (Automatic)
- **When**: During `initialize` (before `call`)
- **What**: Validates `params` against defined `schema`
- **Error**: Raises `ValidationError` if validation fails
- **Skip**: Cannot be skipped

```ruby
schema do
  required(:id).filled(:integer)
  optional(:search).maybe(:string)
end
```

#### Phase 2: Authorization (Optional)
- **When**: Start of `call`, before search
- **What**: Executes `authorize_with` block
- **Error**: Raises `AuthorizationError` if check fails
- **Skip**: Runs only if `authorize_with` is defined

```ruby
authorize_with do
  user.admin? || resource.user_id == user.id
end
```

#### Phase 3: Search
- **When**: After authorization
- **What**: Load raw data from database/APIs
- **Returns**: Hash with `:items` or `:resource` key
- **Customization**: Override `search` method or use `search_with` DSL

```ruby
search_with do
  { items: user.orders.where(status: params[:status]) }
end
```

#### Phase 4: Process
- **When**: After search
- **What**: Transform data, add metadata, business logic
- **Returns**: Hash (usually same keys as search)
- **Customization**: Override `process` method or use `process_with` DSL

```ruby
process_with do |data|
  {
    items: data[:items],
    metadata: { total: data[:items].count }
  }
end
```

#### Phase 5: Transform (Optional)
- **When**: After process
- **What**: Apply presenter or custom transformation
- **Returns**: Transformed data
- **Skip**: Runs only if presenter is configured

```ruby
presenter BookingPresenter
```

#### Phase 6: Respond
- **When**: After transform
- **What**: Format final response with message
- **Returns**: Hash with `:message`, `:success`, data keys
- **Customization**: Override `respond` method or use `respond_with` DSL

```ruby
respond_with do |data|
  success_result("Loaded successfully", data)
end
```

## Service Initialization

All services are initialized with:
- **user**: The current user (required by default)
- **params**: Hash of parameters

```ruby
service = Product::IndexService.new(current_user, params: { search: "laptop" })
result = service.call
```

### User Context

By default, all services require a `user` object:

```ruby
# ✅ Valid
Product::IndexService.new(current_user, params: {})

# ❌ Raises NilUserError
Product::IndexService.new(nil, params: {})
```

To allow `nil` user:

```ruby
class Product::IndexService < BetterService::IndexService
  self._allow_nil_user = true
  # Now can be called without user
end
```

## Return Format

All services return a hash with consistent structure:

```ruby
{
  success: true,                    # Boolean
  message: "Operation successful",  # String
  metadata: {                       # Hash
    action: :index,                 # Symbol (service action)
    # ... additional metadata
  },
  items: [...],                     # Array (for IndexService)
  # OR
  resource: {...}                   # Hash/Object (for other services)
}
```

### Success Response Example

```ruby
{
  success: true,
  message: "Products loaded successfully",
  metadata: {
    action: :index,
    stats: { total: 42 }
  },
  items: [
    { id: 1, name: "Product 1" },
    { id: 2, name: "Product 2" }
  ]
}
```

### Error Handling

Services raise exceptions instead of returning error hashes:

```ruby
begin
  result = Product::CreateService.new(user, params: invalid_params).call
  # If we get here, it succeeded
  product = result[:resource]
rescue BetterService::Errors::Runtime::ValidationError => e
  # Handle validation error
  errors = e.validation_errors
rescue BetterService::Errors::Runtime::AuthorizationError => e
  # Handle authorization error
  message = e.message
end
```

## When to Use Each Service Type

### IndexService
**Use when:**
- Listing multiple resources
- Implementing search/filter
- Building collection endpoints
- Pagination is needed

**Examples:**
- `Product::IndexService` - List all products
- `Order::MyOrdersService` - User's orders
- `Article::SearchService` - Search articles

### ShowService
**Use when:**
- Retrieving single resource by ID
- Need eager loading
- Building detail endpoints
- Resource authorization needed

**Examples:**
- `Product::ShowService` - Product details
- `User::ProfileService` - User profile
- `Order::DetailsService` - Order details

### CreateService
**Use when:**
- Creating new resources
- Need validation and authorization
- Operations require transactions
- Cache invalidation needed

**Examples:**
- `Product::CreateService` - Create product
- `User::RegisterService` - Register user
- `Order::PlaceService` - Place order

### UpdateService
**Use when:**
- Modifying existing resources
- Need to track changes
- Partial updates allowed
- Authorization required

**Examples:**
- `Product::UpdateService` - Update product
- `User::UpdateProfileService` - Update profile
- `Order::CancelService` - Cancel order (status update)

### DestroyService
**Use when:**
- Deleting resources
- Need cleanup of associations
- Soft delete patterns
- Authorization critical

**Examples:**
- `Product::DestroyService` - Delete product
- `User::DeleteAccountService` - Delete account
- `Comment::RemoveService` - Remove comment

### ActionService
**Use when:**
- Custom business logic
- State transitions
- External API integration
- Multi-step processes that don't fit CRUD

**Examples:**
- `Order::ApproveService` - Approve order
- `Article::PublishService` - Publish article
- `Payment::ProcessService` - Process payment
- `Email::SendWelcomeService` - Send email
- `Report::GenerateService` - Generate report

## Service Composition

**IMPORTANT:** Never call services from within other services. Use workflows instead.

### ❌ Anti-Pattern: Calling Services from Services

```ruby
# ❌ DON'T DO THIS
class Order::CreateService < BetterService::CreateService
  process_with do |data|
    order = Order.create!(params)

    # ❌ WRONG: Calling another service directly
    # This lacks automatic rollback and proper error handling
    Payment::ChargeService.new(user, params: {
      order_id: order.id,
      amount: order.total
    }).call

    { resource: order }
  end
end
```

**Why this is bad:**
- No automatic rollback if payment fails
- Order is already created in database
- Difficult to test individual operations
- Tight coupling between services
- No transaction management across services

### ✅ Correct Approach: Use Workflows

For complex multi-step processes with rollback support, use Workflows:

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  step :create_order, with: Order::CreateService
  step :charge_payment, with: Payment::ChargeService
  step :send_confirmation, with: Email::ConfirmationService
end
```

See [Workflows documentation](../workflows/) for details.

## Common Patterns

### Pattern 1: Authorization by Ownership

```ruby
authorize_with do
  resource = Model.find(params[:id])
  resource.user_id == user.id || user.admin?
end
```

### Pattern 2: Conditional Processing

```ruby
process_with do |data|
  resource = data[:resource]

  if params[:notify_user]
    send_notification(resource)
  end

  if params[:publish_immediately]
    resource.publish!
  end

  { resource: resource }
end
```

### Pattern 3: Cache Invalidation

```ruby
class Product::CreateService < BetterService::CreateService
  cache_contexts :products, :category

  process_with do |data|
    product = Product.create!(params)
    invalidate_cache_for(user)  # Invalidates :products and :category
    { resource: product }
  end
end
```

## Next Steps

- **Learn each service type**: Read detailed documentation for each service type
  - [IndexService](02_index_service.md)
  - [ShowService](03_show_service.md)
  - [CreateService](04_create_service.md)
  - [UpdateService](05_update_service.md)
  - [DestroyService](06_destroy_service.md)
  - [ActionService](07_action_service.md)

- **Configuration options**: [Service Configurations](08_service_configurations.md)
- **Generate services**: [Generators Guide](../generators/)
- **Build workflows**: [Workflows Documentation](../workflows/)

---

**See also:**
- [Getting Started](../getting-started.md)
- [Concerns Reference](../concerns-reference.md)
- [Error Handling](../advanced/error-handling.md)
