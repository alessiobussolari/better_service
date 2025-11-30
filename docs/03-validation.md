# Schema Validation

Learn how to validate service parameters with Dry::Schema.

---

## Schema Basics

### Defining a Schema

Every service must define a schema block.

```ruby
class Product::CreateService < Product::BaseService
  schema do
    required(:name).filled(:string)
    required(:price).filled(:decimal, gt?: 0)
    optional(:description).maybe(:string)
  end
end
```

--------------------------------

### When Validation Happens

Validation occurs during service initialization.

```ruby
# Validation happens here (during initialize)
service = Product::CreateService.new(user, params: { name: "", price: -10 })
# => Raises ValidationError immediately

# call is never reached if validation fails
service.call
```

--------------------------------

## Required Fields

### Basic Required Fields

Define mandatory parameters.

```ruby
schema do
  required(:name).filled(:string)
  required(:email).filled(:string)
  required(:age).filled(:integer)
end
```

--------------------------------

### Required with Constraints

Add validation rules to required fields.

```ruby
schema do
  # String constraints
  required(:name).filled(:string, min_size?: 2, max_size?: 100)
  required(:email).filled(:string, format?: /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)

  # Numeric constraints
  required(:price).filled(:decimal, gt?: 0)
  required(:quantity).filled(:integer, gteq?: 1, lteq?: 1000)

  # Inclusion
  required(:status).filled(:string, included_in?: %w[active inactive pending])
end
```

--------------------------------

## Optional Fields

### Basic Optional Fields

Define optional parameters with validation.

```ruby
schema do
  optional(:description).maybe(:string)
  optional(:page).filled(:integer)
  optional(:notes).maybe(:string, max_size?: 500)
end
```

--------------------------------

### Optional vs Maybe

Understanding the difference.

```ruby
schema do
  # optional + filled: parameter can be omitted, but if present must have value
  optional(:page).filled(:integer)
  # Valid: {}, { page: 1 }
  # Invalid: { page: nil }, { page: "" }

  # optional + maybe: parameter can be omitted or be nil
  optional(:notes).maybe(:string)
  # Valid: {}, { notes: nil }, { notes: "text" }
  # Invalid: { notes: 123 }
end
```

--------------------------------

## Type Validation

### Available Types

Common types for validation.

```ruby
schema do
  # Strings
  required(:name).filled(:string)

  # Numbers
  required(:count).filled(:integer)
  required(:price).filled(:decimal)
  required(:rate).filled(:float)

  # Boolean
  required(:active).filled(:bool)

  # Date/Time
  required(:starts_at).filled(:date_time)
  required(:birth_date).filled(:date)

  # Arrays
  required(:tags).filled(:array)

  # Hash
  required(:metadata).filled(:hash)
end
```

--------------------------------

## Numeric Constraints

### Number Validation Rules

Validate numeric ranges and values.

```ruby
schema do
  # Greater than
  required(:price).filled(:decimal, gt?: 0)

  # Greater than or equal
  required(:age).filled(:integer, gteq?: 18)

  # Less than
  required(:discount).filled(:decimal, lt?: 100)

  # Less than or equal
  required(:quantity).filled(:integer, lteq?: 1000)

  # Range (combined)
  required(:rating).filled(:integer, gteq?: 1, lteq?: 5)
end
```

--------------------------------

## String Constraints

### String Validation Rules

Validate string length and format.

```ruby
schema do
  # Minimum length
  required(:name).filled(:string, min_size?: 2)

  # Maximum length
  required(:title).filled(:string, max_size?: 100)

  # Exact length
  required(:code).filled(:string, size?: 6)

  # Length range
  required(:description).filled(:string, min_size?: 10, max_size?: 1000)

  # Format (regex)
  required(:slug).filled(:string, format?: /\A[a-z0-9-]+\z/)
end
```

--------------------------------

## Inclusion Validation

### Validate Against List

Check value is in allowed list.

```ruby
schema do
  # Status must be one of these values
  required(:status).filled(:string, included_in?: %w[draft published archived])

  # Priority level
  required(:priority).filled(:integer, included_in?: [1, 2, 3, 4, 5])

  # Category
  required(:category).filled(:string, included_in?: Category.pluck(:slug))
end
```

--------------------------------

## Array Validation

### Validating Arrays

Validate array parameters.

```ruby
schema do
  # Basic array
  required(:tags).filled(:array)

  # Array with minimum items
  required(:categories).filled(:array, min_size?: 1)

  # Array of specific type (using each)
  required(:ids) do
    array(:integer)
  end
end
```

--------------------------------

## Nested Parameters

### Nested Hash Validation

Validate nested structures.

```ruby
schema do
  required(:product).hash do
    required(:name).filled(:string)
    required(:price).filled(:decimal, gt?: 0)

    optional(:dimensions).hash do
      required(:width).filled(:decimal)
      required(:height).filled(:decimal)
      optional(:depth).maybe(:decimal)
    end
  end
end
```

--------------------------------

## Common Patterns

### ID Parameter

Standard ID validation for Show/Update/Destroy.

```ruby
schema do
  required(:id).filled(:integer)
end
```

--------------------------------

### Pagination Parameters

Standard pagination validation.

```ruby
schema do
  optional(:page).filled(:integer, gteq?: 1)
  optional(:per_page).filled(:integer, gteq?: 1, lteq?: 100)
end
```

--------------------------------

### Search Parameters

Filter and search parameters.

```ruby
schema do
  optional(:search).maybe(:string)
  optional(:status).maybe(:string, included_in?: %w[active inactive])
  optional(:category_id).maybe(:integer)
  optional(:min_price).maybe(:decimal, gteq?: 0)
  optional(:max_price).maybe(:decimal, gt?: 0)
  optional(:sort_by).maybe(:string, included_in?: %w[name price created_at])
  optional(:sort_order).maybe(:string, included_in?: %w[asc desc])
end
```

--------------------------------

## Handling Validation Errors

### Catching ValidationError

Handle validation failures in controllers.

```ruby
class ProductsController < ApplicationController
  def create
    result = Product::CreateService.new(current_user, params: product_params).call

    if result.success?
      render json: { product: result.resource }, status: :created
    else
      render json: { error: result.message }, status: :unprocessable_entity
    end
  rescue BetterService::Errors::Runtime::ValidationError => e
    render json: {
      error: "Validation failed",
      errors: e.context[:validation_errors]
    }, status: :unprocessable_entity
  end
end
```

--------------------------------

### Error Structure

Understanding validation error structure.

```ruby
begin
  Product::CreateService.new(user, params: { name: "", price: -10 })
rescue BetterService::Errors::Runtime::ValidationError => e
  e.code      # => :validation_failed
  e.message   # => "Validation failed"
  e.context[:validation_errors]
  # => {
  #      name: ["must be filled"],
  #      price: ["must be greater than 0"]
  #    }
end
```

--------------------------------

## Best Practices

### Validation Guidelines

Follow these guidelines for effective validation.

```ruby
# 1. Always validate optional params when present
schema do
  optional(:name).filled(:string, min_size?: 2)  # GOOD
  optional(:name)  # BAD - no validation
end

# 2. Use appropriate types
schema do
  required(:price).filled(:decimal, gt?: 0)  # GOOD for money
  required(:price).filled(:float)             # BAD - precision issues
end

# 3. Provide meaningful constraints
schema do
  required(:rating).filled(:integer, gteq?: 1, lteq?: 5)  # GOOD
  required(:rating).filled(:integer)  # BAD - accepts any integer
end

# 4. Use inclusion for known values
schema do
  required(:status).filled(:string, included_in?: %w[active inactive])  # GOOD
  required(:status).filled(:string)  # BAD - accepts any string
end
```

--------------------------------
