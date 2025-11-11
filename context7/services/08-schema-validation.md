# Schema Validation Examples

## Basic Types
Define required and optional fields with types.

```ruby
class Product::CreateService < BetterService::CreateService
  schema do
    # String
    required(:name).filled(:string)
    optional(:description).maybe(:string)

    # Integer
    required(:quantity).filled(:integer)
    optional(:stock).maybe(:integer)

    # Decimal/Float
    required(:price).filled(:decimal)
    optional(:discount).maybe(:float)

    # Boolean
    required(:active).filled(:bool)
    optional(:featured).maybe(:bool)
  end
end
```

## String Validations
Validate string format and size.

```ruby
schema do
  # Format with regex
  required(:email).filled(:string, format?: /@/)
  required(:slug).filled(:string, format?: /\A[a-z0-9-]+\z/)

  # Size constraints
  required(:name).filled(:string, min_size?: 3, max_size?: 100)
  required(:password).filled(:string, min_size?: 8)
  optional(:bio).maybe(:string, max_size?: 500)
end
```

## Number Validations
Validate numeric ranges.

```ruby
schema do
  # Greater than
  required(:price).filled(:decimal, gt?: 0)
  required(:age).filled(:integer, gt?: 18)

  # Greater than or equal
  required(:quantity).filled(:integer, gteq?: 1)

  # Less than
  required(:discount).filled(:float, lt?: 1.0)

  # Range
  required(:rating).filled(:integer, gteq?: 1, lteq?: 5)
  required(:percentage).filled(:integer, gteq?: 0, lteq?: 100)
end
```

## Included In List
Validate against allowed values.

```ruby
schema do
  required(:status).filled(:string, included_in?: %w[draft published archived])
  required(:role).filled(:string, included_in?: %w[user admin moderator])
  required(:payment_method).filled(:string, included_in?: %w[card paypal stripe])
  optional(:sort_by).maybe(:string, included_in?: %w[name price created_at])
end
```

## Nested Hash
Validate nested object structure.

```ruby
schema do
  required(:user).hash do
    required(:email).filled(:string, format?: /@/)
    required(:name).filled(:string)

    optional(:profile).hash do
      optional(:bio).maybe(:string)
      optional(:avatar_url).maybe(:string)
    end
  end
end

# Valid params:
# {
#   user: {
#     email: "user@example.com",
#     name: "John Doe",
#     profile: {
#       bio: "Developer"
#     }
#   }
# }
```

## Array Validation
Validate array of values or objects.

```ruby
schema do
  # Array of integers
  required(:tag_ids).array(:integer)
  optional(:category_ids).array(:integer, min_size?: 1)

  # Array of strings
  optional(:tags).array(:string)

  # Array of hashes
  required(:items).array(:hash) do
    required(:product_id).filled(:integer)
    required(:quantity).filled(:integer, gt?: 0)
    optional(:notes).maybe(:string)
  end
end

# Valid params:
# {
#   tag_ids: [1, 2, 3],
#   items: [
#     { product_id: 1, quantity: 2 },
#     { product_id: 5, quantity: 1, notes: "Gift wrap" }
#   ]
# }
```

## Custom Rules
Add complex validation logic.

```ruby
schema do
  required(:password).filled(:string, min_size?: 8)
  required(:password_confirmation).filled(:string)

  # Custom rule for password confirmation
  rule(:password, :password_confirmation) do
    if values[:password] != values[:password_confirmation]
      key(:password_confirmation).failure('must match password')
    end
  end
end
```

## Date Range Validation
Validate date relationships.

```ruby
schema do
  required(:start_date).filled(:date)
  required(:end_date).filled(:date)

  rule(:start_date, :end_date) do
    if values[:start_date] && values[:end_date]
      if values[:start_date] > values[:end_date]
        key(:end_date).failure('must be after start date')
      end
    end
  end
end
```

## Conditional Validation
Validate based on other fields.

```ruby
schema do
  required(:shipping_method).filled(:string, included_in?: %w[standard express])
  optional(:express_fee).maybe(:decimal)

  rule(:express_fee) do
    if values[:shipping_method] == 'express' && values[:express_fee].nil?
      key.failure('is required for express shipping')
    end
  end
end
```

## Optional with Default
Optional field behavior.

```ruby
schema do
  # Can be nil or absent
  optional(:page).maybe(:integer)

  # Must be integer if provided, can be absent
  optional(:per_page).filled(:integer, gteq?: 1, lteq?: 100)

  # Value type, optional, defaults handled in process
  optional(:sort_direction).maybe(:string, included_in?: %w[asc desc])
end

process_with do |data|
  page = params[:page] || 1
  per_page = params[:per_page] || 20
  direction = params[:sort_direction] || 'asc'

  # Use defaults...
end
```

## Complex Nested Structure
Validate deeply nested data.

```ruby
schema do
  required(:order).hash do
    required(:items).array(:hash) do
      required(:product_id).filled(:integer)
      required(:quantity).filled(:integer, gt?: 0)
      optional(:customization).hash do
        optional(:color).maybe(:string)
        optional(:size).maybe(:string)
      end
    end

    required(:shipping_address).hash do
      required(:street).filled(:string)
      required(:city).filled(:string)
      required(:zip).filled(:string)
      required(:country).filled(:string)
    end

    optional(:billing_address).hash do
      required(:street).filled(:string)
      required(:city).filled(:string)
      required(:zip).filled(:string)
    end
  end
end
```

## Uniqueness Validation
Check uniqueness in search phase.

```ruby
class User::CreateService < BetterService::CreateService
  schema do
    required(:email).filled(:string, format?: /@/)
    required(:username).filled(:string, min_size?: 3)
  end

  search_with do
    # Validate uniqueness
    if User.exists?(email: params[:email].downcase)
      raise BetterService::Errors::Runtime::ValidationError.new(
        "Email already registered"
      )
    end

    if User.exists?(username: params[:username].downcase)
      raise BetterService::Errors::Runtime::ValidationError.new(
        "Username already taken"
      )
    end

    {}
  end

  process_with do |data|
    { resource: User.create!(params) }
  end
end
```

## File Upload Validation
Validate uploaded files (size, type, dimensions).

```ruby
class Document::CreateService < BetterService::CreateService
  model_class Document

  schema do
    required(:title).filled(:string)
    required(:file).hash do
      required(:filename).filled(:string)
      required(:content_type).filled(:string)
      required(:size).filled(:integer)
      optional(:tempfile).filled
    end

    rule(:file) do
      file = value

      # Validate file size (max 10MB)
      if file[:size] > 10.megabytes
        key.failure('file size must be less than 10MB')
      end

      # Validate content type
      allowed_types = %w[application/pdf image/jpeg image/png]
      unless allowed_types.include?(file[:content_type])
        key.failure("file type must be PDF, JPEG, or PNG")
      end

      # Validate filename extension
      extension = File.extname(file[:filename]).downcase
      unless ['.pdf', '.jpg', '.jpeg', '.png'].include?(extension)
        key.failure('invalid file extension')
      end
    end
  end

  process_with do |data|
    document = model_class.create!(
      title: params[:title],
      user: user
    )

    document.file.attach(params[:file])

    { resource: document }
  end
end
```

## Email and URL Format Validation
Validate formats with custom error messages.

```ruby
class Company::CreateService < BetterService::CreateService
  model_class Company

  schema do
    required(:name).filled(:string)
    required(:email).filled(:string)
    required(:website).filled(:string)
    optional(:phone).maybe(:string)

    rule(:email) do
      unless value.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
        key.failure('must be a valid email address (e.g., user@example.com)')
      end
    end

    rule(:website) do
      unless value.match?(/\Ahttps?:\/\/.+\..+\z/)
        key.failure('must be a valid URL (e.g., https://example.com)')
      end

      # Additional check: must be HTTPS in production
      if Rails.env.production? && !value.start_with?('https://')
        key.failure('must use HTTPS in production')
      end
    end

    rule(:phone) do
      if key? && value.present?
        # International format: +1234567890 or (123) 456-7890
        unless value.match?(/\A\+?[\d\s\-\(\)]+\z/)
          key.failure('must be a valid phone number')
        end
      end
    end
  end

  process_with do |data|
    { resource: model_class.create!(params) }
  end
end
```

## Cross-Field Dependencies
Validate that one field requires another.

```ruby
class Subscription::CreateService < BetterService::CreateService
  model_class Subscription

  schema do
    required(:plan).filled(:string, included_in?: %w[free basic premium enterprise])
    optional(:payment_method).maybe(:string)
    optional(:billing_email).maybe(:string)
    optional(:custom_features).maybe(:array)

    # If plan is not free, payment method is required
    rule(:payment_method, :plan) do
      if values[:plan] != 'free' && !values[:payment_method]
        key(:payment_method).failure('is required for paid plans')
      end
    end

    # If plan is not free, billing email is required
    rule(:billing_email, :plan) do
      if values[:plan] != 'free' && !values[:billing_email]
        key(:billing_email).failure('is required for paid plans')
      end
    end

    # Enterprise plan can have custom features
    rule(:custom_features, :plan) do
      if values[:custom_features]&.any? && values[:plan] != 'enterprise'
        key(:custom_features).failure('only available for enterprise plan')
      end
    end

    # Validate billing email format if provided
    rule(:billing_email) do
      if key? && value.present?
        unless value.match?(/\A[^@\s]+@[^@\s]+\z/)
          key.failure('must be a valid email')
        end
      end
    end
  end

  process_with do |data|
    { resource: model_class.create!(params.merge(user: user)) }
  end
end
```

## Dynamic Validation Based on User Role
Different validation rules for different users.

```ruby
class Product::CreateService < BetterService::CreateService
  model_class Product

  schema do
    required(:name).filled(:string)
    required(:price).filled(:decimal, gt?: 0)
    optional(:discount_percentage).maybe(:integer)
    optional(:featured).maybe(:bool)
    optional(:internal_notes).maybe(:string)
  end

  def validate_params
    result = super

    # Additional validations based on user role
    if params[:discount_percentage]
      unless user.admin? || user.manager?
        result.errors.add(:discount_percentage, 'only admins and managers can set discounts')
      end

      # Max discount validation
      max_discount = user.admin? ? 90 : 50
      if params[:discount_percentage] > max_discount
        result.errors.add(:discount_percentage, "cannot exceed #{max_discount}% for your role")
      end
    end

    # Featured products only for admins
    if params[:featured] && !user.admin?
      result.errors.add(:featured, 'only admins can feature products')
    end

    # Internal notes only for employees
    if params[:internal_notes] && !user.employee?
      result.errors.add(:internal_notes, 'not accessible to external users')
    end

    result
  end

  process_with do |data|
    { resource: model_class.create!(params.merge(user: user)) }
  end
end
```
