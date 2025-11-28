# Presenters Guide

BetterService provides a `Presenter` base class for transforming raw model data into view-friendly formats. Presenters decouple your data representation from your ActiveRecord models.

## Table of Contents

- [Overview](#overview)
- [Basic Usage](#basic-usage)
- [Presenter Base Class](#presenter-base-class)
- [Integration with Services](#integration-with-services)
- [Advanced Patterns](#advanced-patterns)
- [Best Practices](#best-practices)

---

## Overview

### What are Presenters?

Presenters are objects that transform raw data (typically ActiveRecord models) into the exact format your API or view needs. They provide:

- **Consistent data formats** - Standardized JSON/Hash output
- **Computed fields** - Calculate derived values
- **Conditional fields** - Show different data based on context
- **Decoupling** - Separate view concerns from model logic

### When to Use Presenters

Use presenters when you need to:
- Format dates, numbers, or currencies
- Include computed fields (e.g., `full_name` from `first_name` + `last_name`)
- Hide sensitive attributes based on user permissions
- Include nested associations in a specific format
- Transform data differently for different contexts (list vs. detail view)

---

## Basic Usage

### Creating a Presenter

```ruby
# app/presenters/product_presenter.rb
class ProductPresenter < BetterService::Presenter
  def as_json(opts = {})
    {
      id: object.id,
      name: object.name,
      price: formatted_price,
      in_stock: object.stock > 0,
      created_at: object.created_at.iso8601
    }
  end

  private

  def formatted_price
    "$#{object.price.round(2)}"
  end
end
```

### Using a Presenter Manually

```ruby
# Create presenter with object
product = Product.find(1)
presenter = ProductPresenter.new(product)

# Get JSON representation
presenter.as_json
# => { id: 1, name: "Widget", price: "$99.99", in_stock: true, created_at: "2025-01-01T00:00:00Z" }

# Get JSON string
presenter.to_json
# => '{"id":1,"name":"Widget","price":"$99.99",...}'

# Get hash (alias for as_json)
presenter.to_h
# => { id: 1, name: "Widget", ... }
```

---

## Presenter Base Class

### Constructor

```ruby
class BetterService::Presenter
  def initialize(object, **options)
    @object = object
    @options = options
  end
end
```

**Parameters:**
- `object` - The object to present (e.g., ActiveRecord model)
- `options` - Additional options hash (e.g., `current_user`, `fields`)

### Available Methods

| Method | Description |
|--------|-------------|
| `object` | The wrapped object being presented |
| `options` | The options hash passed to constructor |
| `current_user` | Shortcut for `options[:current_user]` |
| `as_json(opts = {})` | Override to define JSON representation |
| `to_json(opts = {})` | Returns JSON string |
| `to_h` | Alias for `as_json` |
| `include_field?(field)` | Check if field should be included |
| `user_can?(role)` | Check if current user has a role |

### Helper Methods

#### `current_user`

Access the current user from options:

```ruby
class ProductPresenter < BetterService::Presenter
  def as_json(opts = {})
    base = { id: object.id, name: object.name }

    # Add admin-only fields
    if current_user&.admin?
      base[:cost] = object.cost
      base[:margin] = object.price - object.cost
    end

    base
  end
end

# Usage
ProductPresenter.new(product, current_user: admin_user).as_json
```

#### `include_field?(field)`

Check if a field should be included based on options:

```ruby
class ProductPresenter < BetterService::Presenter
  def as_json(opts = {})
    result = {
      id: object.id,
      name: object.name
    }

    # Only include if requested
    result[:description] = object.description if include_field?(:description)
    result[:reviews] = present_reviews if include_field?(:reviews)

    result
  end
end

# Usage with field selection
ProductPresenter.new(product, fields: [:description]).as_json
```

#### `user_can?(role)`

Check user permissions:

```ruby
class OrderPresenter < BetterService::Presenter
  def as_json(opts = {})
    base = { id: object.id, total: object.total }

    # Only managers see profit margin
    if user_can?(:manager)
      base[:profit] = object.total - object.cost
    end

    base
  end
end
```

---

## Integration with Services

### Using `presenter` DSL

Services can declare a presenter using the `presenter` DSL:

```ruby
class Products::ShowService < BetterService::ShowService
  model_class Product
  presenter ProductPresenter

  search_with do
    { resource: model_class.find(params[:id]) }
  end
end
```

### Using `presenter_options` DSL

Pass options to presenters:

```ruby
class Products::IndexService < BetterService::IndexService
  model_class Product
  presenter ProductPresenter

  presenter_options do
    {
      current_user: user,
      fields: params[:fields]&.split(',')&.map(&:to_sym)
    }
  end

  search_with do
    { items: model_class.all.to_a }
  end
end

# Controller usage
result = Products::IndexService.new(
  current_user,
  params: { fields: "name,price,description" }
).call

# Presenter receives:
# - object: each product
# - current_user: current_user
# - fields: [:name, :price, :description]
```

### Manual Transformation with `transform_with`

For custom transformation logic:

```ruby
class Products::IndexService < BetterService::IndexService
  model_class Product

  search_with do
    { items: model_class.all.to_a }
  end

  transform_with do |data|
    {
      items: data[:items].map do |product|
        ProductPresenter.new(product, current_user: user).as_json
      end
    }
  end
end
```

---

## Advanced Patterns

### Different Presenters for Different Contexts

```ruby
# Lightweight presenter for lists
class ProductListPresenter < BetterService::Presenter
  def as_json(opts = {})
    {
      id: object.id,
      name: object.name,
      price: formatted_price
    }
  end
end

# Detailed presenter for single resource
class ProductDetailPresenter < BetterService::Presenter
  def as_json(opts = {})
    {
      id: object.id,
      name: object.name,
      description: object.description,
      price: formatted_price,
      category: CategoryPresenter.new(object.category).as_json,
      reviews: object.reviews.map { |r| ReviewPresenter.new(r).as_json },
      images: object.images.map(&:url)
    }
  end
end

# Use in services
class Products::IndexService < BetterService::IndexService
  presenter ProductListPresenter
end

class Products::ShowService < BetterService::ShowService
  presenter ProductDetailPresenter
end
```

### Nested Presenters

```ruby
class OrderPresenter < BetterService::Presenter
  def as_json(opts = {})
    {
      id: object.id,
      number: object.number,
      total: formatted_total,
      status: object.status,
      customer: CustomerPresenter.new(object.customer, **options).as_json,
      items: object.line_items.map { |li| LineItemPresenter.new(li).as_json },
      shipping_address: AddressPresenter.new(object.shipping_address).as_json
    }
  end
end
```

### Conditional Fields Based on User

```ruby
class UserPresenter < BetterService::Presenter
  def as_json(opts = {})
    base_fields.merge(conditional_fields)
  end

  private

  def base_fields
    {
      id: object.id,
      name: object.name,
      avatar_url: object.avatar_url
    }
  end

  def conditional_fields
    result = {}

    # User can see their own email
    result[:email] = object.email if viewing_self?

    # Admins can see everything
    if current_user&.admin?
      result[:email] = object.email
      result[:role] = object.role
      result[:created_at] = object.created_at
      result[:last_login] = object.last_login_at
    end

    result
  end

  def viewing_self?
    current_user&.id == object.id
  end
end
```

### Computed Fields

```ruby
class ProductPresenter < BetterService::Presenter
  def as_json(opts = {})
    {
      id: object.id,
      name: object.name,
      price: object.price,

      # Computed fields
      discounted_price: calculate_discount,
      rating: average_rating,
      review_count: object.reviews.count,
      availability: availability_status
    }
  end

  private

  def calculate_discount
    return object.price unless object.discount_percentage

    (object.price * (1 - object.discount_percentage / 100.0)).round(2)
  end

  def average_rating
    object.reviews.average(:rating)&.round(1) || 0.0
  end

  def availability_status
    case object.stock
    when 0 then "out_of_stock"
    when 1..5 then "low_stock"
    else "in_stock"
    end
  end
end
```

### Formatting Helpers

```ruby
class BasePresenter < BetterService::Presenter
  private

  def format_money(amount, currency: "$")
    return nil if amount.nil?
    "#{currency}#{amount.round(2)}"
  end

  def format_date(datetime, format: :default)
    return nil if datetime.nil?

    case format
    when :short then datetime.strftime("%b %d")
    when :long then datetime.strftime("%B %d, %Y")
    when :iso8601 then datetime.iso8601
    else datetime.strftime("%Y-%m-%d")
    end
  end

  def format_percentage(value)
    return nil if value.nil?
    "#{(value * 100).round(1)}%"
  end
end

class OrderPresenter < BasePresenter
  def as_json(opts = {})
    {
      id: object.id,
      total: format_money(object.total),
      tax: format_money(object.tax),
      discount: format_percentage(object.discount_rate),
      ordered_at: format_date(object.created_at, format: :long),
      delivered_at: format_date(object.delivered_at, format: :short)
    }
  end
end
```

---

## Best Practices

### 1. Keep Presenters Focused

```ruby
# GOOD: Single responsibility
class ProductPresenter < BetterService::Presenter
  def as_json(opts = {})
    # Only product-related fields
  end
end

# BAD: Mixed responsibilities
class ProductPresenter < BetterService::Presenter
  def as_json(opts = {})
    {
      product: product_data,
      user: user_data,      # Should be separate presenter
      settings: app_settings # Not related to product
    }
  end
end
```

### 2. Avoid N+1 Queries

```ruby
# BAD: N+1 query in presenter
class OrderPresenter < BetterService::Presenter
  def as_json(opts = {})
    {
      items: object.line_items.map { |li|
        # Each line_item triggers a product query
        product: li.product.name
      }
    }
  end
end

# GOOD: Eager load in service
class Orders::ShowService < BetterService::ShowService
  search_with do
    { resource: Order.includes(line_items: :product).find(params[:id]) }
  end
end
```

### 3. Use Presenter Options for Context

```ruby
# GOOD: Pass context via options
ProductPresenter.new(product,
  current_user: user,
  include_admin_fields: user.admin?,
  locale: I18n.locale
).as_json

# BAD: Access global state
class ProductPresenter < BetterService::Presenter
  def as_json(opts = {})
    # Accessing Current.user or similar globals
    if Current.user.admin?  # Avoid this
      # ...
    end
  end
end
```

### 4. Test Your Presenters

```ruby
class ProductPresenterTest < ActiveSupport::TestCase
  test "presents basic product attributes" do
    product = Product.new(id: 1, name: "Widget", price: 99.99, stock: 10)
    presenter = ProductPresenter.new(product)

    result = presenter.as_json

    assert_equal 1, result[:id]
    assert_equal "Widget", result[:name]
    assert_equal "$99.99", result[:price]
    assert result[:in_stock]
  end

  test "includes admin fields for admin users" do
    product = Product.new(id: 1, name: "Widget", cost: 50.0, price: 99.99)
    admin = User.new(role: "admin")

    result = ProductPresenter.new(product, current_user: admin).as_json

    assert_equal 50.0, result[:cost]
    assert_equal 49.99, result[:margin]
  end

  test "excludes admin fields for regular users" do
    product = Product.new(id: 1, name: "Widget", cost: 50.0, price: 99.99)
    user = User.new(role: "customer")

    result = ProductPresenter.new(product, current_user: user).as_json

    assert_nil result[:cost]
    assert_nil result[:margin]
  end
end
```

### 5. Document Expected Output

```ruby
# app/presenters/product_presenter.rb

# ProductPresenter
#
# Presents Product model data for API responses.
#
# Output format:
#   {
#     id: Integer,
#     name: String,
#     price: String (formatted: "$XX.XX"),
#     in_stock: Boolean,
#     created_at: String (ISO8601),
#     # Admin only:
#     cost: Float,
#     margin: Float
#   }
#
class ProductPresenter < BetterService::Presenter
  # ...
end
```

---

## Generator

Generate a presenter with:

```bash
rails generate better_service:presenter Product
```

This creates:
- `app/presenters/product_presenter.rb` - Presenter class
- `test/presenters/product_presenter_test.rb` - Test file

---

## See Also

- **Micro-examples**: `/context7/services/12-presenters.md` - Quick patterns
- **Presentable Concern**: `/docs/concerns-reference.md#presentable` - Service integration
- **Service Configuration**: `/docs/services/08_service_configurations.md` - DSL options
