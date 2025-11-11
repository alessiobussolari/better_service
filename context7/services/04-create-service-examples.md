# CreateService Examples

## Basic Creation
Create a new resource with validation.

```ruby
class Product::CreateService < BetterService::CreateService
  model_class Product

  schema do
    required(:name).filled(:string)
    required(:price).filled(:decimal, gt?: 0)
    optional(:description).maybe(:string)
  end

  process_with do |data|
    resource = model_class.create!(params)
    { resource: resource }
  end
end

# Usage
result = Product::CreateService.new(current_user, params: {
  name: "Laptop",
  price: 999.99
}).call
product = result[:resource]
```

## With User Association
Automatically associate created resource with current user.

```ruby
class Post::CreateService < BetterService::CreateService
  model_class Post

  schema do
    required(:title).filled(:string)
    required(:content).filled(:string)
  end

  process_with do |data|
    resource = model_class.create!(params.merge(user: user))
    { resource: resource }
  end
end
```

## With Authorization
Ensure only authorized users can create.

```ruby
class Product::CreateService < BetterService::CreateService
  model_class Product

  authorize_with do
    user.admin? || user.has_permission?(:create_products)
  end

  schema do
    required(:name).filled(:string)
    required(:price).filled(:decimal)
  end

  process_with do |data|
    resource = model_class.create!(params)
    { resource: resource }
  end
end
```

## With Cache Invalidation
Invalidate related caches after creation.

```ruby
class Product::CreateService < BetterService::CreateService
  model_class Product
  cache_contexts :products, :category_products

  schema do
    required(:name).filled(:string)
    required(:price).filled(:decimal)
  end

  process_with do |data|
    resource = model_class.create!(params.merge(user: user))

    # Automatically invalidates :products and :category_products caches
    invalidate_cache_for(user)

    { resource: resource }
  end
end
```

## With Nested Attributes
Create resource with associated records.

```ruby
class Order::CreateService < BetterService::CreateService
  model_class Order

  schema do
    required(:items).array(:hash) do
      required(:product_id).filled(:integer)
      required(:quantity).filled(:integer, gt?: 0)
    end
  end

  process_with do |data|
    order = model_class.create!(user: user)

    params[:items].each do |item|
      order.items.create!(
        product_id: item[:product_id],
        quantity: item[:quantity]
      )
    end

    { resource: order }
  end
end
```

## With Business Logic in Search
Validate business rules before creation.

```ruby
class Order::CreateService < BetterService::CreateService
  model_class Order

  schema do
    required(:cart_id).filled(:integer)
  end

  search_with do
    cart = Cart.find(params[:cart_id])

    # Validate business rules
    if cart.items.empty?
      raise BetterService::Errors::Runtime::ValidationError.new(
        "Cart is empty"
      )
    end

    { cart: cart }
  end

  process_with do |data|
    cart = data[:cart]
    order = model_class.create!(user: user, total: cart.total)

    # Create order items from cart
    cart.items.each do |cart_item|
      order.items.create!(
        product: cart_item.product,
        quantity: cart_item.quantity,
        price: cart_item.product.price
      )
    end

    { resource: order }
  end
end
```

## With File Upload
Handle file attachments during creation.

```ruby
class Product::CreateService < BetterService::CreateService
  model_class Product

  schema do
    required(:name).filled(:string)
    required(:price).filled(:decimal)
    optional(:images).array(:hash)
  end

  process_with do |data|
    resource = model_class.create!(params.except(:images))

    # Attach images after creation
    params[:images]&.each do |image|
      resource.images.attach(image)
    end

    { resource: resource }
  end
end
```

## With Presenter
Format created resource for output.

```ruby
class Product::CreateService < BetterService::CreateService
  model_class Product
  presenter ProductPresenter

  schema do
    required(:name).filled(:string)
    required(:price).filled(:decimal)
  end

  process_with do |data|
    resource = model_class.create!(params.merge(user: user))
    invalidate_cache_for(user)
    { resource: resource }
  end
end
```

## With Custom Validation Rules
Add complex validation logic.

```ruby
class User::CreateService < BetterService::CreateService
  model_class User

  schema do
    required(:email).filled(:string, format?: /@/)
    required(:password).filled(:string, min_size?: 8)
    required(:password_confirmation).filled(:string)

    rule(:password, :password_confirmation) do
      if values[:password] != values[:password_confirmation]
        key(:password_confirmation).failure('must match password')
      end
    end
  end

  search_with do
    # Check uniqueness
    if User.exists?(email: params[:email].downcase)
      raise BetterService::Errors::Runtime::ValidationError.new(
        "Email already registered"
      )
    end
    {}
  end

  process_with do |data|
    resource = model_class.create!(
      email: params[:email].downcase,
      password: params[:password]
    )
    { resource: resource }
  end
end
```

## Transaction Rollback Example
All changes roll back on error.

```ruby
class Order::CreateService < BetterService::CreateService
  model_class Order
  # Transactions are ON by default

  process_with do |data|
    order = model_class.create!(user: user, total: 100)
    order.items.create!(product_id: 1, quantity: 2)

    # If this fails, order and items are rolled back
    Payment.charge!(order.total)

    { resource: order }
  end
end
```

## Prevent Duplicates
Check for existing records before creating.

```ruby
class Contact::CreateService < BetterService::CreateService
  model_class Contact

  schema do
    required(:email).filled(:string, format?: /@/)
    required(:name).filled(:string)
  end

  search_with do
    # Check for existing contact
    existing = model_class.find_by(
      email: params[:email].downcase,
      user_id: user.id
    )

    if existing
      raise BetterService::Errors::Runtime::ValidationError.new(
        "Contact with email #{params[:email]} already exists"
      )
    end

    {}
  end

  process_with do |data|
    resource = model_class.create!(
      params.merge(
        email: params[:email].downcase,
        user_id: user.id
      )
    )
    { resource: resource }
  end
end
```

## Auto-Increment Custom IDs
Generate sequential invoice or order numbers.

```ruby
class Invoice::CreateService < BetterService::CreateService
  model_class Invoice

  schema do
    required(:order_id).filled(:integer)
    required(:amount).filled(:decimal)
  end

  search_with do
    order = Order.find(params[:order_id])

    # Generate next invoice number
    last_invoice = model_class.order(invoice_number: :desc).first
    next_number = last_invoice ? last_invoice.invoice_number + 1 : 1000

    { order: order, invoice_number: next_number }
  end

  process_with do |data|
    resource = model_class.create!(
      order_id: params[:order_id],
      amount: params[:amount],
      invoice_number: data[:invoice_number],
      issued_at: Time.current
    )
    { resource: resource }
  end
end
```

## Create with Webhook Notification
Notify external systems after creation.

```ruby
class User::CreateService < BetterService::CreateService
  model_class User

  schema do
    required(:email).filled(:string)
    required(:name).filled(:string)
  end

  process_with do |data|
    resource = model_class.create!(params)

    # Notify external CRM system
    begin
      CrmWebhook.notify_new_user(resource)
    rescue StandardError => e
      # Log but don't fail creation
      Rails.logger.error("CRM notification failed: #{e.message}")
      Sentry.capture_exception(e)
    end

    { resource: resource }
  end
end
```

## Multi-Step Validation with Inventory
Check inventory before creating order.

```ruby
class Order::CreateService < BetterService::CreateService
  model_class Order

  schema do
    required(:items).filled(:array) do
      hash do
        required(:product_id).filled(:integer)
        required(:quantity).filled(:integer, gt?: 0)
      end
    end
  end

  search_with do
    # Validate inventory for all items
    params[:items].each do |item|
      product = Product.find(item[:product_id])

      if product.stock < item[:quantity]
        raise BetterService::Errors::Runtime::ValidationError.new(
          "Insufficient stock for #{product.name}. " \
          "Available: #{product.stock}, Requested: #{item[:quantity]}"
        )
      end
    end

    { validated: true }
  end

  process_with do |data|
    order = model_class.create!(user: user, status: 'pending')

    # Create order items and decrease inventory
    params[:items].each do |item|
      product = Product.find(item[:product_id])

      order.order_items.create!(
        product: product,
        quantity: item[:quantity],
        price: product.price
      )

      product.decrement!(:stock, item[:quantity])
    end

    order.update!(total: order.order_items.sum('quantity * price'))

    { resource: order }
  end
end
```
