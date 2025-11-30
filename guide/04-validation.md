# Validation

Master schema validation with Dry::Schema.

---

## Schema Basics

### Every Service Needs a Schema

All services must define a schema block, even if empty.

```ruby
# Minimal schema (no params required)
class Status::CheckService < BetterService::Services::Base
  schema { }

  process_with do
    { resource: { status: "ok" } }
  end
end

# Service without schema raises SchemaRequiredError
class BadService < BetterService::Services::Base
  # Missing schema! Will fail.
end
```

--------------------------------

## Required Fields

### Basic Required Field

Define fields that must be present.

```ruby
schema do
  required(:name).filled(:string)
  required(:email).filled(:string)
  required(:age).filled(:integer)
end

# Valid params: { name: "John", email: "john@example.com", age: 30 }
# Missing field raises ValidationError
```

--------------------------------

### Multiple Required Fields

Combine multiple required fields.

```ruby
schema do
  required(:title).filled(:string)
  required(:body).filled(:string)
  required(:author_id).filled(:integer)
  required(:published_at).filled(:date_time)
end
```

--------------------------------

## Optional Fields

### Basic Optional Field

Define fields that may be omitted.

```ruby
schema do
  required(:name).filled(:string)
  optional(:nickname).filled(:string)
  optional(:bio).filled(:string)
end

# Valid: { name: "John" }
# Valid: { name: "John", nickname: "Johnny" }
# Valid: { name: "John", nickname: "Johnny", bio: "Developer" }
```

--------------------------------

### Optional with Default Handling

Handle missing optional fields in your service.

```ruby
schema do
  required(:amount).filled(:decimal)
  optional(:currency).filled(:string)
end

process_with do
  amount = params[:amount]
  currency = params[:currency] || "USD"  # Default in service

  { resource: { amount: amount, currency: currency } }
end
```

--------------------------------

## Type Constraints

### Common Types

Available types for validation.

```ruby
schema do
  required(:name).filled(:string)
  required(:count).filled(:integer)
  required(:price).filled(:decimal)
  required(:active).filled(:bool)
  required(:created_at).filled(:date_time)
  required(:birth_date).filled(:date)
  required(:tags).filled(:array)
  required(:metadata).filled(:hash)
end
```

--------------------------------

### Type Coercion

Dry::Schema can coerce types.

```ruby
schema do
  # String "123" becomes integer 123
  required(:id).filled(:integer)

  # String "99.99" becomes decimal
  required(:price).filled(:decimal)

  # String "true" becomes boolean
  required(:active).filled(:bool)
end

# Input:  { id: "123", price: "99.99", active: "true" }
# Params: { id: 123, price: 99.99, active: true }
```

--------------------------------

## Value Constraints

### Minimum and Maximum

Set numeric bounds.

```ruby
schema do
  required(:age).filled(:integer, gteq?: 18, lteq?: 120)
  required(:price).filled(:decimal, gt?: 0)
  required(:quantity).filled(:integer, gteq?: 1, lteq?: 100)
end

# gteq? = greater than or equal
# lteq? = less than or equal
# gt? = greater than
# lt? = less than
```

--------------------------------

### String Length

Set string length constraints.

```ruby
schema do
  required(:username).filled(:string, min_size?: 3, max_size?: 20)
  required(:password).filled(:string, min_size?: 8)
  required(:bio).filled(:string, max_size?: 500)
end
```

--------------------------------

### Format Validation

Validate string formats with regex.

```ruby
schema do
  required(:email).filled(:string, format?: /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i)
  required(:phone).filled(:string, format?: /\A\d{10}\z/)
  required(:slug).filled(:string, format?: /\A[a-z0-9-]+\z/)
end
```

--------------------------------

### Inclusion

Validate value is in a set.

```ruby
schema do
  required(:status).filled(:string, included_in?: %w[draft published archived])
  required(:role).filled(:string, included_in?: %w[admin user guest])
  required(:priority).filled(:integer, included_in?: [1, 2, 3, 4, 5])
end
```

--------------------------------

## Nested Structures

### Nested Hash

Validate nested objects.

```ruby
schema do
  required(:user).hash do
    required(:name).filled(:string)
    required(:email).filled(:string)
    optional(:profile).hash do
      optional(:bio).filled(:string)
      optional(:avatar_url).filled(:string)
    end
  end
end

# Valid params:
# {
#   user: {
#     name: "John",
#     email: "john@example.com",
#     profile: {
#       bio: "Developer"
#     }
#   }
# }
```

--------------------------------

### Array of Hashes

Validate arrays of objects.

```ruby
schema do
  required(:items).array(:hash) do
    required(:product_id).filled(:integer)
    required(:quantity).filled(:integer, gt?: 0)
    optional(:notes).filled(:string)
  end
end

# Valid params:
# {
#   items: [
#     { product_id: 1, quantity: 2 },
#     { product_id: 2, quantity: 1, notes: "Gift wrap" }
#   ]
# }
```

--------------------------------

### Array of Simple Values

Validate arrays of primitives.

```ruby
schema do
  required(:tags).array(:string)
  required(:category_ids).array(:integer)
  optional(:scores).array(:decimal)
end

# Valid: { tags: ["ruby", "rails"], category_ids: [1, 2, 3] }
```

--------------------------------

## Maybe Types

### Allow Nil Values

Use maybe for nullable fields.

```ruby
schema do
  required(:name).filled(:string)
  required(:deleted_at).maybe(:date_time)  # Can be nil or DateTime
  optional(:parent_id).maybe(:integer)     # Can be nil or Integer
end

# Valid: { name: "John", deleted_at: nil }
# Valid: { name: "John", deleted_at: "2024-01-01T00:00:00Z" }
```

--------------------------------

## Validation Errors

### Error Structure

ValidationError provides detailed error information.

```ruby
begin
  Product::CreateService.new(user, params: { name: "", price: -10 })
rescue BetterService::Errors::Runtime::ValidationError => e
  e.code     # => :validation_failed
  e.message  # => "Validation failed"
  e.context[:validation_errors]
  # => {
  #   name: ["must be filled"],
  #   price: ["must be greater than 0"]
  # }
end
```

--------------------------------

### Handling in Controllers

Handle validation errors gracefully.

```ruby
def create
  result = Product::CreateService.new(current_user, params: product_params).call
  render json: { product: result.resource }, status: :created
rescue BetterService::Errors::Runtime::ValidationError => e
  render json: {
    error: "Validation failed",
    errors: e.context[:validation_errors]
  }, status: :unprocessable_entity
end
```

--------------------------------

## Common Patterns

### Create Service Schema

Typical create service validation.

```ruby
class Product::CreateService < Product::BaseService
  schema do
    required(:name).filled(:string, min_size?: 2, max_size?: 100)
    required(:price).filled(:decimal, gt?: 0, lteq?: 999999.99)
    required(:category_id).filled(:integer, gt?: 0)
    optional(:description).filled(:string, max_size?: 5000)
    optional(:sku).filled(:string, format?: /\A[A-Z0-9-]+\z/)
    optional(:tags).array(:string)
  end
end
```

--------------------------------

### Update Service Schema

Update service with id and optional fields.

```ruby
class Product::UpdateService < Product::BaseService
  schema do
    required(:id).filled(:integer, gt?: 0)
    optional(:name).filled(:string, min_size?: 2, max_size?: 100)
    optional(:price).filled(:decimal, gt?: 0)
    optional(:description).filled(:string)
    optional(:category_id).filled(:integer, gt?: 0)
  end
end
```

--------------------------------

### Search/Filter Schema

Index service with filter options.

```ruby
class Product::IndexService < Product::BaseService
  schema do
    optional(:page).filled(:integer, gteq?: 1)
    optional(:per_page).filled(:integer, gteq?: 1, lteq?: 100)
    optional(:sort_by).filled(:string, included_in?: %w[name price created_at])
    optional(:sort_dir).filled(:string, included_in?: %w[asc desc])
    optional(:category).filled(:string)
    optional(:min_price).filled(:decimal, gteq?: 0)
    optional(:max_price).filled(:decimal, gt?: 0)
    optional(:search).filled(:string, min_size?: 2)
  end
end
```

--------------------------------

## Testing Validation

### Test Required Fields

Verify required fields are validated.

```ruby
test "validates name is required" do
  error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
    Product::CreateService.new(@user, params: { price: 99.99 })
  end

  assert error.context[:validation_errors].key?(:name)
  assert_includes error.context[:validation_errors][:name], "is missing"
end
```

--------------------------------

### Test Value Constraints

Verify value constraints work.

```ruby
test "validates price must be positive" do
  error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
    Product::CreateService.new(@user, params: { name: "Widget", price: -10 })
  end

  assert error.context[:validation_errors].key?(:price)
end

test "validates name minimum length" do
  error = assert_raises(BetterService::Errors::Runtime::ValidationError) do
    Product::CreateService.new(@user, params: { name: "X", price: 99.99 })
  end

  assert error.context[:validation_errors].key?(:name)
end
```

--------------------------------

## Next Steps

### Continue Learning

What to learn next.

```ruby
# Now that you understand validation:

# 1. Learn repositories
#    → guide/05-repositories.md

# 2. Build workflows
#    → guide/06-workflows.md
```

--------------------------------
