# Authorization

Master permission patterns in BetterService.

---

## The Golden Rule

### Use `next` Not `return`

This is critical - using return causes LocalJumpError.

```ruby
# WRONG - Will raise LocalJumpError!
authorize_with do
  return true if user.admin?
  return false unless user.active?
  user.can_access?
end

# CORRECT - Use next for early exits
authorize_with do
  next true if user.admin?
  next false unless user.active?
  user.can_access?
end
```

--------------------------------

## Basic Authorization

### Simple Permission Check

The simplest authorization pattern.

```ruby
class Report::ViewService < BetterService::Services::Base
  schema do
    required(:id).filled(:integer)
  end

  authorize_with do
    user.can_view_reports?
  end

  # ... rest of service
end
```

--------------------------------

### Boolean Result

The block must return a truthy or falsy value.

```ruby
authorize_with do
  # Returns true → authorized
  # Returns false/nil → unauthorized

  user.admin? || user.manager?
end
```

--------------------------------

## Admin Bypass Pattern

### Check Admin First

Always check admin status before resource lookup for efficiency.

```ruby
# CORRECT - Admin check first (fast path)
authorize_with do
  next true if user.admin?  # Skip expensive lookups

  # Only non-admins reach this code
  resource = Product.find_by(id: params[:id])
  next false unless resource

  resource.user_id == user.id
end

# WRONG - Unnecessary lookup for admins
authorize_with do
  resource = Product.find_by(id: params[:id])  # Runs for everyone
  return true if user.admin?
  resource&.user_id == user.id
end
```

--------------------------------

## Ownership Patterns

### Owner Check

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

### Team Membership

Check if user belongs to the same team.

```ruby
authorize_with do
  next true if user.admin?

  project = Project.find_by(id: params[:id])
  next false unless project

  project.team.members.include?(user)
end
```

--------------------------------

### Organization Access

Verify organization membership.

```ruby
authorize_with do
  next true if user.admin?

  document = Document.find_by(id: params[:id])
  next false unless document

  user.organization_id == document.organization_id
end
```

--------------------------------

## Role-Based Authorization

### Multiple Roles

Check for specific roles.

```ruby
authorize_with do
  next true if user.admin?
  next true if user.role == "manager"
  next true if user.role == "editor"

  false  # Default deny
end
```

--------------------------------

### Permission-Based

Check specific permissions.

```ruby
authorize_with do
  next true if user.admin?

  user.permissions.include?("products.create")
end
```

--------------------------------

### Hierarchical Roles

Role hierarchy with levels.

```ruby
authorize_with do
  # Define role hierarchy
  role_levels = {
    "viewer" => 1,
    "editor" => 2,
    "manager" => 3,
    "admin" => 4
  }

  required_level = role_levels["editor"]
  user_level = role_levels[user.role] || 0

  user_level >= required_level
end
```

--------------------------------

## Context-Aware Authorization

### Status-Based Access

Different rules based on resource status.

```ruby
authorize_with do
  next true if user.admin?

  document = Document.find_by(id: params[:id])
  next false unless document

  case document.status
  when "draft"
    document.author_id == user.id
  when "review"
    document.reviewers.include?(user)
  when "published"
    true  # Anyone can view published
  else
    false
  end
end
```

--------------------------------

### Time-Based Access

Restrict access based on time.

```ruby
authorize_with do
  next true if user.admin?

  # Only allow during business hours
  current_hour = Time.current.hour
  next false unless (9..17).cover?(current_hour)

  user.active?
end
```

--------------------------------

## Allow Nil User

### Public Services

Allow services to run without a user.

```ruby
class Product::PublicShowService < BetterService::Services::Base
  allow_nil_user  # User can be nil

  schema do
    required(:id).filled(:integer)
  end

  authorize_with do
    # When allow_nil_user is set, user may be nil
    next true if user.nil?  # Public access
    next true if user.admin?

    product = Product.find_by(id: params[:id])
    product&.published?
  end

  # ... rest of service
end

# Usage - works with nil user
result = Product::PublicShowService.new(nil, params: { id: 1 }).call
```

--------------------------------

## Combining Conditions

### Complex Logic

Combine multiple authorization rules.

```ruby
authorize_with do
  next true if user.admin?

  # Must be active
  next false unless user.active?

  # Must have verified email
  next false unless user.email_verified?

  # Must be in correct department
  document = Document.find_by(id: params[:id])
  next false unless document

  # Same department or explicit permission
  user.department_id == document.department_id ||
    document.shared_with?(user)
end
```

--------------------------------

### And/Or Conditions

Using boolean operators.

```ruby
# AND - all conditions must be true
authorize_with do
  user.active? && user.verified? && user.subscription_active?
end

# OR - any condition can be true
authorize_with do
  user.admin? || user.moderator? || user.owner_of?(params[:id])
end

# Mixed
authorize_with do
  next true if user.admin?

  user.active? && (user.role == "editor" || user.role == "manager")
end
```

--------------------------------

## Authorization Failure

### What Happens on Failure

When authorization fails, a failure result is returned.

```ruby
result = Product::UpdateService.new(non_owner, params: { id: 1 }).call

result.success?          # => false
result.meta[:error_code] # => :unauthorized
result.message           # => "Not authorized"
```

--------------------------------

### Handling in Controllers

Handle authorization failures appropriately.

```ruby
def update
  result = Product::UpdateService.new(current_user, params: update_params).call

  if result.success?
    render json: { product: result.resource }
  elsif result.meta[:error_code] == :unauthorized
    render json: { error: "You cannot modify this product" }, status: :forbidden
  else
    render json: { error: result.message }, status: :unprocessable_entity
  end
end
```

--------------------------------

## Testing Authorization

### Test Different User Types

Verify authorization for each user type.

```ruby
class Product::UpdateServiceTest < ActiveSupport::TestCase
  setup do
    @product = products(:widget)
    @owner = @product.user
    @admin = users(:admin)
    @other_user = users(:other)
  end

  test "admin can update any product" do
    result = Product::UpdateService.new(
      @admin,
      params: { id: @product.id, name: "New Name" }
    ).call

    assert result.success?
  end

  test "owner can update own product" do
    result = Product::UpdateService.new(
      @owner,
      params: { id: @product.id, name: "New Name" }
    ).call

    assert result.success?
  end

  test "other user cannot update product" do
    result = Product::UpdateService.new(
      @other_user,
      params: { id: @product.id, name: "New Name" }
    ).call

    refute result.success?
    assert_equal :unauthorized, result.meta[:error_code]
  end
end
```

--------------------------------

## Best Practices

### Authorization Guidelines

Follow these patterns for clean authorization.

```ruby
# 1. Always check admin first
authorize_with do
  next true if user.admin?
  # ... other checks
end

# 2. Use next for early returns
authorize_with do
  next true if user.admin?
  next false unless user.active?
  user.can_access?
end

# 3. Keep authorization simple
# If logic is complex, extract to a method
authorize_with do
  next true if user.admin?
  can_access_product?(params[:id])
end

private

def can_access_product?(product_id)
  product = Product.find_by(id: product_id)
  return false unless product
  product.user_id == user.id || product.public?
end

# 4. Default to deny
authorize_with do
  next true if user.admin?
  next true if user.role == "manager"
  false  # Explicit deny
end
```

--------------------------------

## Next Steps

### Continue Learning

What to learn next.

```ruby
# Now that you understand authorization:

# 1. Master validation
#    → guide/04-validation.md

# 2. Learn repositories
#    → guide/05-repositories.md
```

--------------------------------
