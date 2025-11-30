# Anti-Patterns

Common mistakes and how to fix them.

---

## Using return in authorize_with

### Problem

`return` causes `LocalJumpError` because blocks don't support `return`.

```ruby
# WRONG - LocalJumpError!
authorize_with do
  return true if user.admin?
  return false unless product
  product.user_id == user.id
end
```

--------------------------------

### Solution

Use `next` instead of `return`.

```ruby
# CORRECT
authorize_with do
  next true if user.admin?
  product = Product.find_by(id: params[:id])
  next false unless product
  product.user_id == user.id
end
```

--------------------------------

## Missing { resource: } Wrapper

### Problem

Resource extraction fails without proper hash wrapper.

```ruby
# WRONG - Resource won't be extracted
process_with do |data|
  product_repository.create!(params)
end

# WRONG - Returns wrong structure
process_with do |data|
  product = product_repository.create!(params)
  product  # Just returns the object, not a hash
end
```

--------------------------------

### Solution

Always return `{ resource: object }`.

```ruby
# CORRECT
process_with do |data|
  product = product_repository.create!(params)
  { resource: product }
end

# For collections
process_with do |data|
  products = product_repository.all
  { items: products }
end
```

--------------------------------

## Calling Services from Services

### Problem

No automatic rollback if nested service fails.

```ruby
# WRONG - No rollback on payment failure
class Order::CreateService < Order::BaseService
  process_with do |data|
    order = order_repository.create!(params)

    # If this fails, order is NOT rolled back!
    Payment::ChargeService.new(user, params: { order_id: order.id }).call

    { resource: order }
  end
end
```

--------------------------------

### Solution

Use workflows for service composition.

```ruby
# CORRECT - Automatic rollback on failure
class Order::CheckoutWorkflow < BetterService::Workflows::Base
  with_transaction true

  step :create_order,
       with: Order::CreateService,
       input: ->(ctx) { ctx.params }

  step :charge_payment,
       with: Payment::ChargeService,
       input: ->(ctx) { { order_id: ctx.create_order.id } },
       rollback: ->(ctx) { Payment::RefundService.new(ctx.user, params: { id: ctx.charge_payment.id }).call }
end
```

--------------------------------

## Missing Schema Definition

### Problem

Service initialization fails with `SchemaRequiredError`.

```ruby
# WRONG - SchemaRequiredError raised
class Product::CreateService < Product::BaseService
  performed_action :created

  # No schema block!

  process_with do |data|
    { resource: product_repository.create!(params) }
  end
end
```

--------------------------------

### Solution

Always define a schema block.

```ruby
# CORRECT
class Product::CreateService < Product::BaseService
  performed_action :created

  schema do
    required(:name).filled(:string)
    required(:price).filled(:decimal, gt?: 0)
  end

  process_with do |data|
    { resource: product_repository.create!(params) }
  end
end

# For services with no required params
schema do
  optional(:page).filled(:integer)
end
```

--------------------------------

## Database Queries in authorize_with

### Problem

Wasted queries before authorization fails.

```ruby
# WRONG - Queries database before checking admin
authorize_with do
  product = Product.includes(:variants, :reviews).find(params[:id])
  next true if user.admin?
  product.user_id == user.id
end
```

--------------------------------

### Solution

Check admin first, use minimal queries.

```ruby
# CORRECT - Admin bypass FIRST
authorize_with do
  next true if user.admin?  # No query needed for admins

  # Minimal query for non-admins
  product = Product.find_by(id: params[:id])
  next false unless product
  product.user_id == user.id
end
```

--------------------------------

## with_transaction on Read Operations

### Problem

Unnecessary transaction overhead on read-only operations.

```ruby
# WRONG - Transaction not needed
class Product::IndexService < Product::BaseService
  performed_action :listed
  with_transaction true  # Unnecessary!

  search_with do
    { items: product_repository.all }
  end
end
```

--------------------------------

### Solution

Only use transactions for write operations.

```ruby
# CORRECT - No transaction for reads
class Product::IndexService < Product::BaseService
  performed_action :listed
  # No with_transaction

  search_with do
    { items: product_repository.all }
  end
end

# Use transactions only for writes
class Product::CreateService < Product::BaseService
  with_transaction true  # Correct usage
end
```

--------------------------------

## Complex Branch Conditions

### Problem

Hard to read and maintain.

```ruby
# WRONG - Unreadable conditions
branch do
  on ->(ctx) { ctx.order.type == "subscription" && ctx.order.recurring? && ctx.user.premium? && ctx.payment.method == "card" && !ctx.order.trial? } do
    step :premium_subscription_card, with: PremiumSubscriptionCardService
  end
end
```

--------------------------------

### Solution

Use nested branches for decision trees.

```ruby
# CORRECT - Clear decision tree
branch do
  on ->(ctx) { ctx.order.type == "subscription" } do
    branch do
      on ->(ctx) { ctx.user.premium? } do
        step :premium_subscription, with: PremiumSubscriptionService
      end
      otherwise do
        step :standard_subscription, with: StandardSubscriptionService
      end
    end
  end

  otherwise do
    step :one_time_purchase, with: OneTimePurchaseService
  end
end
```

--------------------------------

## Ignoring Optional Step Failures

### Problem

Silent failures may cause issues downstream.

```ruby
# WRONG - Ignoring failure silently
step :send_notification,
     with: Notification::SendService,
     optional: true

step :update_analytics,
     with: Analytics::UpdateService,
     input: ->(ctx) { { notification_sent: ctx.send_notification.sent? } }  # May be nil!
```

--------------------------------

### Solution

Handle optional step results properly.

```ruby
# CORRECT - Check for optional step result
step :send_notification,
     with: Notification::SendService,
     optional: true

step :update_analytics,
     with: Analytics::UpdateService,
     input: ->(ctx) {
       {
         notification_sent: ctx.send_notification&.sent? || false
       }
     }
```

--------------------------------

## Direct Model Access in respond_with

### Problem

Accessing models directly instead of using data parameter.

```ruby
# WRONG - Direct model access
class Product::CreateService < Product::BaseService
  process_with do |_data|
    @product = product_repository.create!(params)  # Instance variable
    { resource: @product }
  end

  respond_with do |data|
    success_result(message("create.success", name: @product.name), data)  # Using @product
  end
end
```

--------------------------------

### Solution

Always use the data parameter.

```ruby
# CORRECT - Use data parameter
class Product::CreateService < Product::BaseService
  process_with do |_data|
    product = product_repository.create!(params)
    { resource: product }
  end

  respond_with do |data|
    success_result(message("create.success", name: data[:resource].name), data)
  end
end
```

--------------------------------

## Hardcoded Error Messages

### Problem

Non-internationalized, hard to maintain.

```ruby
# WRONG - Hardcoded strings
process_with do |data|
  if data[:resource].published?
    raise ExecutionError.new("This product is already published")
  end
end
```

--------------------------------

### Solution

Use I18n message helper.

```ruby
# CORRECT - Internationalized
process_with do |data|
  if data[:resource].published?
    raise ExecutionError.new(
      message("publish.already_published"),
      context: { id: data[:resource].id }
    )
  end
end
```

--------------------------------

## Missing Error Context

### Problem

Hard to debug without context.

```ruby
# WRONG - No context
raise ResourceNotFoundError.new("Product not found")
```

--------------------------------

### Solution

Always include relevant context.

```ruby
# CORRECT - Rich context
raise ResourceNotFoundError.new(
  "Product not found",
  context: {
    id: params[:id],
    model_class: "Product",
    user_id: user.id
  }
)
```

--------------------------------

## Skipping Validation on Optional Params

### Problem

Invalid data may slip through.

```ruby
# WRONG - No validation on optional params
schema do
  required(:id).filled(:integer)
  optional(:name)  # No validation!
  optional(:price) # No validation!
end
```

--------------------------------

### Solution

Validate optional params when present.

```ruby
# CORRECT - Validate optional params
schema do
  required(:id).filled(:integer)
  optional(:name).filled(:string, min_size?: 2)
  optional(:price).filled(:decimal, gt?: 0)
end
```

--------------------------------

## Quick Reference

### Anti-Pattern Summary Table

Quick reference for common mistakes and fixes.

```ruby
# Anti-Pattern                    | Fix
# --------------------------------|----------------------------------
# return in authorize_with        | Use next
# Missing { resource: }           | Always wrap in hash
# Service calls service           | Use workflow
# No schema block                 | Always define schema
# Complex queries in auth         | Admin check first
# Transaction on reads            | Only for writes
# Complex branch conditions       | Use nested branches
# Ignoring optional failures      | Check for nil
# Direct model in respond_with    | Use data parameter
# Hardcoded messages              | Use I18n
# Missing error context           | Include context hash
# No optional param validation    | Validate when present
```

--------------------------------
