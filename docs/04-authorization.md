# Authorization

Learn how to implement authorization in BetterService.

---

## Authorization Basics

### The authorize_with Block

Define authorization logic using the authorize_with DSL.

```ruby
class Product::UpdateService < Product::BaseService
  authorize_with do
    next true if user.admin?
    product = Product.find_by(id: params[:id])
    next false unless product
    product.user_id == user.id
  end
end
```

--------------------------------

### When Authorization Runs

Authorization executes during `call`, before search phase.

```ruby
# 1. Validation (initialize) - schema validation
service = Product::UpdateService.new(user, params: { id: 1 })

# 2. Authorization (call) - authorize_with block
# 3. Search
# 4. Process
# 5. Respond
result = service.call
```

--------------------------------

## Critical Rule: Use next

### Never Use return

Use `next` instead of `return` in authorize_with blocks.

```ruby
# WRONG - Causes LocalJumpError!
authorize_with do
  return true if user.admin?
  return false unless product
end

# CORRECT - Use next
authorize_with do
  next true if user.admin?
  product = Product.find_by(id: params[:id])
  next false unless product
  product.user_id == user.id
end
```

--------------------------------

## Common Patterns

### Admin Bypass Pattern

Always check admin status first.

```ruby
authorize_with do
  next true if user.admin?  # Admin bypass FIRST

  # Then check specific permissions
  product = Product.find_by(id: params[:id])
  next false unless product
  product.user_id == user.id
end
```

--------------------------------

### Role-Based Authorization

Check user roles.

```ruby
authorize_with do
  next true if user.admin?
  next true if user.manager?
  user.seller?  # Returns boolean, no next needed for last statement
end
```

--------------------------------

### Resource Ownership

Verify the user owns the resource.

```ruby
authorize_with do
  next true if user.admin?

  product = Product.find_by(id: params[:id])
  next false unless product

  product.user_id == user.id
end
```

--------------------------------

### Public/Published Resources

Allow access to public resources.

```ruby
authorize_with do
  next true if user.admin?

  product = Product.find_by(id: params[:id])
  next false unless product

  # Allow if published (public) or user owns it
  product.published? || product.user_id == user.id
end
```

--------------------------------

### Organization-Based Access

Check organization membership.

```ruby
authorize_with do
  next true if user.admin?

  product = Product.find_by(id: params[:id])
  next false unless product

  # User must belong to the same organization
  user.organization_id == product.organization_id
end
```

--------------------------------

### Team-Based Access

Check team membership.

```ruby
authorize_with do
  next true if user.admin?

  project = Project.find_by(id: params[:id])
  next false unless project

  # User must be a team member
  project.team_members.include?(user)
end
```

--------------------------------

## Create Service Authorization

### Authorization for New Resources

Create services often just check roles.

```ruby
class Product::CreateService < Product::BaseService
  authorize_with do
    next true if user.admin?
    user.seller?  # Only sellers can create products
  end
end
```

--------------------------------

### With Category Restrictions

Check if user can create in category.

```ruby
class Product::CreateService < Product::BaseService
  authorize_with do
    next true if user.admin?
    next false unless user.seller?

    # Check if user can create in this category
    category = Category.find_by(id: params[:category_id])
    next false unless category

    user.allowed_categories.include?(category)
  end
end
```

--------------------------------

## Index Service Authorization

### Scoped Queries

Authorization can influence data scope.

```ruby
class Product::IndexService < Product::BaseService
  # No authorize_with needed - filtering happens in search_with

  search_with do
    scope = if user.admin?
      Product.all
    else
      Product.where(user_id: user.id).or(Product.where(published: true))
    end

    { items: scope.page(params[:page]) }
  end
end
```

--------------------------------

## Handling Authorization Failure

### Authorization Result

When authorization fails, service returns failure result.

```ruby
result = Product::UpdateService.new(user, params: { id: 1 }).call

unless result.success?
  result.meta[:error_code]  # => :unauthorized
  result.message            # => "Not authorized"
end
```

--------------------------------

### Controller Handling

Handle authorization failure in controllers.

```ruby
class ProductsController < ApplicationController
  def update
    result = Product::UpdateService.new(current_user, params: update_params).call

    if result.success?
      render json: { product: result.resource }
    else
      case result.meta[:error_code]
      when :unauthorized
        render json: { error: "You don't have permission" }, status: :forbidden
      when :resource_not_found
        render json: { error: "Product not found" }, status: :not_found
      else
        render json: { error: result.message }, status: :unprocessable_entity
      end
    end
  end
end
```

--------------------------------

## Allow Nil User

### Public Services

Allow services to run without a user.

```ruby
class Product::ShowService < Product::BaseService
  allow_nil_user  # Permit nil user

  authorize_with do
    product = Product.find_by(id: params[:id])
    next false unless product

    # Public products accessible to anyone
    next true if product.published?

    # Private products require owner
    user.present? && product.user_id == user.id
  end
end

# Can be called without user
Product::ShowService.new(nil, params: { id: 1 }).call
```

--------------------------------

## Performance Tips

### Minimize Queries

Optimize authorization for performance.

```ruby
# WRONG - Heavy query before admin check
authorize_with do
  product = Product.includes(:variants, :reviews).find(params[:id])
  next true if user.admin?  # Too late!
  product.user_id == user.id
end

# CORRECT - Admin check first, minimal query
authorize_with do
  next true if user.admin?  # No query needed

  # Minimal query for non-admins
  product = Product.select(:id, :user_id).find_by(id: params[:id])
  next false unless product
  product.user_id == user.id
end
```

--------------------------------

### Use Exists Queries

For existence checks, use exists? instead of find.

```ruby
# CORRECT - Efficient existence check
authorize_with do
  next true if user.admin?

  # Efficient: just checks existence
  Project.where(id: params[:id], team_members: user).exists?
end
```

--------------------------------

## Complex Authorization

### Multiple Conditions

Combine multiple authorization rules.

```ruby
authorize_with do
  next true if user.admin?

  product = Product.find_by(id: params[:id])
  next false unless product

  # Must be owner
  next false unless product.user_id == user.id

  # Can't modify if sold
  next false if product.sold?

  # Can't modify if in review
  next false if product.under_review?

  true
end
```

--------------------------------

### Time-Based Authorization

Restrict actions based on time.

```ruby
authorize_with do
  next true if user.admin?

  auction = Auction.find_by(id: params[:id])
  next false unless auction

  # Can only bid during active period
  auction.started? && !auction.ended? && auction.user_id != user.id
end
```

--------------------------------

## Best Practices

### Authorization Guidelines

Follow these guidelines for authorization.

```ruby
# 1. Always check admin first
authorize_with do
  next true if user.admin?  # Always first
  # Other checks...
end

# 2. Use minimal queries
authorize_with do
  next true if user.admin?
  Product.select(:user_id).find_by(id: params[:id])&.user_id == user.id
end

# 3. Be explicit about failures
authorize_with do
  next true if user.admin?
  product = Product.find_by(id: params[:id])
  next false unless product  # Explicit failure
  product.user_id == user.id
end

# 4. Document complex logic
authorize_with do
  next true if user.admin?

  # User must be either:
  # 1. The product owner, OR
  # 2. A team member with edit permission
  product = Product.find_by(id: params[:id])
  next false unless product

  product.user_id == user.id ||
    product.team_permissions.where(user: user, can_edit: true).exists?
end
```

--------------------------------
