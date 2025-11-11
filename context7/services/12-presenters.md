# Presenter Examples

## Basic Presenter
Format single resource output.

```ruby
class Product::ShowService < BetterService::ShowService
  model_class Product
  presenter ProductPresenter

  search_with do
    { resource: model_class.find(params[:id]) }
  end
end

class ProductPresenter
  def self.present(product)
    {
      id: product.id,
      name: product.name,
      price: product.price.to_f,
      created_at: product.created_at.iso8601
    }
  end
end

# Result: { resource: { id: 1, name: "Laptop", price: 999.99, created_at: "2024-01-01T00:00:00Z" } }
```

## Collection Presenter
Format array of resources.

```ruby
class Product::IndexService < BetterService::IndexService
  model_class Product
  presenter ProductPresenter

  search_with do
    { items: model_class.all }
  end
end

class ProductPresenter
  def self.present(product)
    {
      id: product.id,
      name: product.name,
      price: product.price.to_f
    }
  end
end

# Each item in :items array is formatted by presenter
```

## Nested Associations
Include related data in presentation.

```ruby
class ProductPresenter
  def self.present(product)
    {
      id: product.id,
      name: product.name,
      price: product.price.to_f,
      category: {
        id: product.category.id,
        name: product.category.name
      },
      images: product.images.map { |img| img.url }
    }
  end
end
```

## Conditional Fields
Show different fields based on context.

```ruby
class UserPresenter
  def self.present(user, options = {})
    base = {
      id: user.id,
      name: user.name,
      avatar: user.avatar.url
    }

    # Add email only for detailed view
    if options[:detailed]
      base[:email] = user.email
      base[:created_at] = user.created_at
    end

    base
  end
end

# Usage in service
class User::ShowService < BetterService::ShowService
  def transform(data)
    presenter = UserPresenter.present(
      data[:resource],
      detailed: params[:detailed]
    )
    { resource: presenter }
  end
end
```

## Computed Fields
Add calculated values.

```ruby
class ProductPresenter
  def self.present(product)
    {
      id: product.id,
      name: product.name,
      price: product.price.to_f,
      # Computed fields
      discounted_price: calculate_discount(product),
      rating: product.reviews.average(:rating)&.round(1),
      review_count: product.reviews.count,
      in_stock: product.stock > 0
    }
  end

  private

  def self.calculate_discount(product)
    return product.price unless product.discount_percentage

    product.price * (1 - product.discount_percentage / 100.0)
  end
end
```

## Format Dates and Numbers
Consistent formatting.

```ruby
class OrderPresenter
  def self.present(order)
    {
      id: order.id,
      number: order.number,
      total: format_money(order.total),
      subtotal: format_money(order.subtotal),
      tax: format_money(order.tax),
      created_at: format_date(order.created_at),
      updated_at: format_date(order.updated_at)
    }
  end

  private

  def self.format_money(amount)
    "$#{amount.round(2)}"
  end

  def self.format_date(datetime)
    datetime.strftime("%B %d, %Y at %I:%M %p")
  end
end
```

## Multiple Presenters
Different formats for different contexts.

```ruby
# Simple presenter for lists
class ProductListPresenter
  def self.present(product)
    {
      id: product.id,
      name: product.name,
      price: product.price.to_f
    }
  end
end

# Detailed presenter for single resource
class ProductDetailPresenter
  def self.present(product)
    {
      id: product.id,
      name: product.name,
      description: product.description,
      price: product.price.to_f,
      category: product.category.name,
      images: product.images.map(&:url),
      reviews: product.reviews.map { |r| ReviewPresenter.present(r) }
    }
  end
end

# Usage
class Product::IndexService < BetterService::IndexService
  presenter ProductListPresenter
end

class Product::ShowService < BetterService::ShowService
  presenter ProductDetailPresenter
end
```

## Active Model Serializer Style
Use instance methods.

```ruby
class ProductPresenter
  attr_reader :product

  def initialize(product)
    @product = product
  end

  def as_json
    {
      id: product.id,
      name: product.name,
      price: formatted_price,
      category: category_json
    }
  end

  private

  def formatted_price
    "$#{product.price.round(2)}"
  end

  def category_json
    {
      id: product.category.id,
      name: product.category.name
    }
  end

  class << self
    def present(product)
      new(product).as_json
    end
  end
end
```
