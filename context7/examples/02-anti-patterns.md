# Anti-Patterns Examples

## ❌ Using def process Instead of DSL
NEVER override the process method directly.

**❌ WRONG:**
```ruby
class Product::CreateService < BetterService::CreateService
  model_class Product

  # ❌ DON'T DO THIS
  def process(data)
    resource = model_class.create!(params)
    { resource: resource }
  end
end
```

**✅ CORRECT:**
```ruby
class Product::CreateService < BetterService::CreateService
  model_class Product

  # ✅ Use the DSL method
  process_with do |data|
    resource = model_class.create!(params)
    { resource: resource }
  end
end
```

## ❌ Calling Services from Services
NEVER call one service from another service.

**❌ WRONG:**
```ruby
class Order::CreateService < BetterService::CreateService
  model_class Order

  process_with do |data|
    order = model_class.create!(params)

    # ❌ DON'T DO THIS - calling service from service
    Payment::ChargeService.new(user, params: {
      order_id: order.id,
      amount: order.total
    }).call

    { resource: order }
  end
end
```

**✅ CORRECT:**
```ruby
# Use a workflow instead
class Order::CheckoutWorkflow < BetterService::Workflow
  step :create_order, with: Order::CreateService
  step :charge_payment, with: Payment::ChargeService
end
```

## ❌ Using def search Instead of DSL
NEVER override the search method.

**❌ WRONG:**
```ruby
class Product::ShowService < BetterService::ShowService
  model_class Product

  # ❌ DON'T DO THIS
  def search
    { resource: model_class.find(params[:id]) }
  end
end
```

**✅ CORRECT:**
```ruby
class Product::ShowService < BetterService::ShowService
  model_class Product

  # ✅ Use the DSL method
  search_with do
    { resource: model_class.find(params[:id]) }
  end
end
```

## ❌ Using def respond Instead of DSL
NEVER override the respond method.

**❌ WRONG:**
```ruby
class Product::ShowService < BetterService::ShowService
  model_class Product

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  # ❌ DON'T DO THIS
  def respond(data)
    { resource: format_product(data[:resource]) }
  end

  private

  def format_product(product)
    { id: product.id, name: product.name }
  end
end
```

**✅ CORRECT:**
```ruby
class Product::ShowService < BetterService::ShowService
  model_class Product
  presenter ProductPresenter

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  # ✅ Use presenter or respond_with
  respond_with do |data|
    { resource: format_product(data[:resource]) }
  end

  private

  def format_product(product)
    { id: product.id, name: product.name }
  end
end
```

## ❌ Missing Transaction Wrapping
NEVER perform multiple database operations without transactions.

**❌ WRONG:**
```ruby
class Order::CreateService < BetterService::CreateService
  model_class Order

  process_with do |data|
    # ❌ Multiple operations without transaction
    order = model_class.create!(params)
    OrderItem.create!(order_id: order.id, product_id: params[:product_id])
    Inventory.decrement!(params[:product_id])

    { resource: order }
  end
end
```

**✅ CORRECT:**
```ruby
class Order::CreateService < BetterService::CreateService
  model_class Order

  # ✅ Use workflow for automatic transactions
  # Or use ActiveRecord::Base.transaction manually
  process_with do |data|
    ActiveRecord::Base.transaction do
      order = model_class.create!(params)
      OrderItem.create!(order_id: order.id, product_id: params[:product_id])
      Inventory.decrement!(params[:product_id])

      { resource: order }
    end
  end
end

# ✅ Better: Use workflow
class Order::CreateWorkflow < BetterService::Workflow
  step :create_order, with: Order::CreateService
  step :create_items, with: OrderItem::CreateService
  step :update_inventory, with: Inventory::UpdateService
end
```

## ❌ Missing Authorization
NEVER skip authorization checks for sensitive operations.

**❌ WRONG:**
```ruby
class User::DestroyService < BetterService::DestroyService
  model_class User

  # ❌ No authorization - any user can delete any user!
  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    data[:resource].destroy!
    { resource: data[:resource] }
  end
end
```

**✅ CORRECT:**
```ruby
class User::DestroyService < BetterService::DestroyService
  model_class User

  # ✅ Proper authorization
  authorize_with do
    user.admin? || data[:resource].id == user.id
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    data[:resource].destroy!
    { resource: data[:resource] }
  end
end
```

## ❌ Direct Database Queries in Controllers
NEVER bypass services in controllers.

**❌ WRONG:**
```ruby
class ProductsController < ApplicationController
  def index
    # ❌ Direct query in controller
    @products = Product.where(category: params[:category])
                      .page(params[:page])
  end

  def create
    # ❌ Direct create in controller
    @product = Product.create!(product_params)
  end
end
```

**✅ CORRECT:**
```ruby
class ProductsController < ApplicationController
  def index
    # ✅ Use service
    result = Product::IndexService.new(current_user, params: index_params).call
    @products = result[:items]
  end

  def create
    # ✅ Use service
    result = Product::CreateService.new(current_user, params: create_params).call
    @product = result[:resource]
  end
end
```

## ❌ Fat Services
NEVER put too much logic in a single service.

**❌ WRONG:**
```ruby
class Order::CreateService < BetterService::CreateService
  model_class Order

  process_with do |data|
    # ❌ Too much logic in one service
    order = model_class.create!(params)

    # Charging payment
    charge = Stripe::Charge.create(
      amount: order.total,
      currency: 'usd'
    )

    # Sending emails
    OrderMailer.confirmation(order).deliver_later
    OrderMailer.invoice(order).deliver_later

    # Updating inventory
    order.items.each do |item|
      item.product.decrement!(:stock)
    end

    { resource: order }
  end
end
```

**✅ CORRECT:**
```ruby
# ✅ Break into multiple services and use workflow
class Order::CheckoutWorkflow < BetterService::Workflow
  step :create_order, with: Order::CreateService
  step :charge_payment, with: Payment::ChargeService
  step :update_inventory, with: Inventory::UpdateService
  step :send_confirmation, with: Email::ConfirmationService
  step :send_invoice, with: Email::InvoiceService
end
```
