# E-commerce Example

Complete e-commerce implementation using BetterService, covering products, shopping cart, checkout, and order processing.

## Table of Contents

- [Overview](#overview)
- [Models](#models)
- [Product Services](#product-services)
- [Cart Services](#cart-services)
- [Order Services](#order-services)
- [Checkout Workflow](#checkout-workflow)
- [Controllers](#controllers)
- [Testing](#testing)

---

## Overview

This example demonstrates a complete e-commerce system with:
- **Product Management** - CRUD operations for products
- **Shopping Cart** - Add/remove items, calculate totals
- **Checkout Process** - Multi-step workflow with payment
- **Order Processing** - Order creation and fulfillment
- **Authorization** - Role-based access control
- **Caching** - Performance optimization
- **Transactions** - Data integrity

---

## Models

### Product Model

```ruby
# app/models/product.rb
class Product < ApplicationRecord
  belongs_to :user
  has_many :cart_items, dependent: :destroy
  has_many :order_items, dependent: :destroy

  validates :name, presence: true
  validates :sku, presence: true, uniqueness: true
  validates :price, numericality: { greater_than: 0 }
  validates :stock, numericality: { greater_than_or_equal_to: 0 }

  after_commit :invalidate_product_cache, on: [:create, :update, :destroy]

  private

  def invalidate_product_cache
    BetterService::CacheService.invalidate_global("products")
  end
end
```

---

### Cart Model

```ruby
# app/models/cart.rb
class Cart < ApplicationRecord
  belongs_to :user
  has_many :cart_items, dependent: :destroy
  has_many :products, through: :cart_items

  def total
    cart_items.sum { |item| item.product.price * item.quantity }
  end

  def empty?
    cart_items.count.zero?
  end

  def clear!
    cart_items.destroy_all
  end
end
```

---

### CartItem Model

```ruby
# app/models/cart_item.rb
class CartItem < ApplicationRecord
  belongs_to :cart
  belongs_to :product

  validates :quantity, numericality: { greater_than: 0 }
  validate :stock_available

  private

  def stock_available
    if product && quantity > product.stock
      errors.add(:quantity, "exceeds available stock")
    end
  end
end
```

---

### Order Model

```ruby
# app/models/order.rb
class Order < ApplicationRecord
  belongs_to :user
  has_many :order_items, dependent: :destroy
  has_one :payment, dependent: :destroy

  enum status: {
    pending: "pending",
    confirmed: "confirmed",
    shipped: "shipped",
    delivered: "delivered",
    cancelled: "cancelled"
  }

  validates :total, numericality: { greater_than: 0 }

  def can_cancel?
    pending? || confirmed?
  end
end
```

---

## Product Services

### Product::IndexService

```ruby
# app/services/product/index_service.rb
class Product::IndexService < BetterService::Services::IndexService
  cache_key "products_index"
  cache_ttl 1.hour
  cache_contexts :products

  schema do
    optional(:category).maybe(:string)
    optional(:search).maybe(:string)
    optional(:min_price).maybe(:decimal, gteq?: 0)
    optional(:max_price).maybe(:decimal, gteq?: 0)
    optional(:page).maybe(:integer, gteq?: 1)
    optional(:per_page).maybe(:integer, gteq?: 1, lteq?: 100)
  end

  search_with do
    products = Product.where(published: true)

    # Filter by category
    products = products.where(category: params[:category]) if params[:category]

    # Search by name or description
    if params[:search]
      products = products.where(
        "name LIKE ? OR description LIKE ?",
        "%#{params[:search]}%",
        "%#{params[:search]}%"
      )
    end

    # Filter by price range
    products = products.where("price >= ?", params[:min_price]) if params[:min_price]
    products = products.where("price <= ?", params[:max_price]) if params[:max_price]

    { items: products.to_a }
  end

  process_with do |data|
    page = params[:page] || 1
    per_page = params[:per_page] || 20
    items = data[:items]

    # Pagination
    offset = (page - 1) * per_page
    paginated_items = items[offset, per_page] || []

    {
      items: paginated_items,
      metadata: {
        total: items.count,
        page: page,
        per_page: per_page,
        pages: (items.count / per_page.to_f).ceil
      }
    }
  end
end
```

---

### Product::CreateService

```ruby
# app/services/product/create_service.rb
class Product::CreateService < BetterService::Services::CreateService
  cache_contexts :products

  schema do
    required(:name).filled(:string)
    required(:sku).filled(:string)
    required(:price).filled(:decimal, gt?: 0)
    required(:stock).filled(:integer, gteq?: 0)
    optional(:description).maybe(:string)
    optional(:category).maybe(:string)
    optional(:published).maybe(:bool)
  end

  authorize_with do
    user.admin? || user.vendor?
  end

  process_with do |data|
    product = user.products.create!(
      name: params[:name],
      sku: params[:sku],
      price: params[:price],
      stock: params[:stock],
      description: params[:description],
      category: params[:category],
      published: params[:published] || false
    )

    invalidate_cache_for(user)

    { resource: product }
  end
end
```

---

### Product::UpdateService

```ruby
# app/services/product/update_service.rb
class Product::UpdateService < BetterService::Services::UpdateService
  cache_contexts :products

  schema do
    required(:id).filled(:integer)
    optional(:name).filled(:string)
    optional(:price).filled(:decimal, gt?: 0)
    optional(:stock).filled(:integer, gteq?: 0)
    optional(:description).maybe(:string)
    optional(:published).maybe(:bool)
  end

  authorize_with do
    product = Product.find(params[:id])
    user.admin? || product.user_id == user.id
  end

  search_with do
    { resource: user.products.find(params[:id]) }
  end

  process_with do |data|
    product = data[:resource]
    product.update!(params.except(:id))

    invalidate_cache_for(user)

    { resource: product }
  end
end
```

---

## Cart Services

### Cart::AddItemService

```ruby
# app/services/cart/add_item_service.rb
class Cart::AddItemService < BetterService::Services::ActionService
  action_name :add_item

  schema do
    required(:product_id).filled(:integer)
    required(:quantity).filled(:integer, gt?: 0)
  end

  search_with do
    {
      cart: user.cart || user.create_cart!,
      product: Product.find(params[:product_id])
    }
  end

  process_with do |data|
    cart = data[:cart]
    product = data[:product]

    # Check stock availability
    if params[:quantity] > product.stock
      raise BetterService::Errors::Runtime::ExecutionError.new(
        "Insufficient stock",
        code: :insufficient_stock,
        context: { available: product.stock, requested: params[:quantity] }
      )
    end

    # Find or create cart item
    cart_item = cart.cart_items.find_or_initialize_by(product: product)
    cart_item.quantity ||= 0
    cart_item.quantity += params[:quantity]
    cart_item.save!

    {
      resource: cart_item,
      metadata: {
        cart_total: cart.total,
        cart_items_count: cart.cart_items.count
      }
    }
  end
end
```

---

### Cart::RemoveItemService

```ruby
# app/services/cart/remove_item_service.rb
class Cart::RemoveItemService < BetterService::Services::ActionService
  action_name :remove_item

  schema do
    required(:cart_item_id).filled(:integer)
  end

  search_with do
    {
      cart: user.cart,
      cart_item: user.cart.cart_items.find(params[:cart_item_id])
    }
  end

  process_with do |data|
    cart_item = data[:cart_item]
    cart = data[:cart]

    cart_item.destroy!

    {
      resource: cart,
      metadata: {
        cart_total: cart.total,
        cart_items_count: cart.cart_items.count
      }
    }
  end
end
```

---

### Cart::UpdateQuantityService

```ruby
# app/services/cart/update_quantity_service.rb
class Cart::UpdateQuantityService < BetterService::Services::ActionService
  action_name :update_quantity

  schema do
    required(:cart_item_id).filled(:integer)
    required(:quantity).filled(:integer, gt?: 0)
  end

  search_with do
    {
      cart_item: user.cart.cart_items.find(params[:cart_item_id])
    }
  end

  process_with do |data|
    cart_item = data[:cart_item]

    # Check stock
    if params[:quantity] > cart_item.product.stock
      raise BetterService::Errors::Runtime::ExecutionError.new(
        "Insufficient stock",
        code: :insufficient_stock
      )
    end

    cart_item.update!(quantity: params[:quantity])

    {
      resource: cart_item,
      metadata: {
        cart_total: cart_item.cart.total
      }
    }
  end
end
```

---

## Order Services

### Order::CreateService

```ruby
# app/services/order/create_service.rb
class Order::CreateService < BetterService::Services::CreateService
  schema do
    required(:cart_id).filled(:integer)
    required(:shipping_address).hash do
      required(:street).filled(:string)
      required(:city).filled(:string)
      required(:state).filled(:string)
      required(:zip).filled(:string)
    end
  end

  search_with do
    cart = user.carts.find(params[:cart_id])

    if cart.empty?
      raise BetterService::Errors::Runtime::ExecutionError.new(
        "Cart is empty",
        code: :empty_cart
      )
    end

    { cart: cart }
  end

  process_with do |data|
    cart = data[:cart]

    order = user.orders.create!(
      total: cart.total,
      status: "pending",
      shipping_address: params[:shipping_address]
    )

    # Create order items from cart items
    cart.cart_items.each do |cart_item|
      order.order_items.create!(
        product: cart_item.product,
        quantity: cart_item.quantity,
        price: cart_item.product.price
      )
    end

    { resource: order }
  end
end
```

---

## Checkout Workflow

### Order::CheckoutWorkflow

Complete checkout process with payment, inventory, and notifications.

```ruby
# app/workflows/order/checkout_workflow.rb
class Order::CheckoutWorkflow < BetterService::Workflow
  with_transaction true

  before_workflow :validate_cart
  after_workflow :clear_cart_on_success

  # Step 1: Calculate order total with discounts
  step :calculate_total,
       with: Order::CalculateTotalService,
       input: ->(ctx) {
         {
           cart_id: ctx.params[:cart_id],
           coupon_code: ctx.params[:coupon_code]
         }
       }

  # Step 2: Validate stock availability
  step :validate_stock,
       with: Inventory::ValidateStockService,
       input: ->(ctx) { { cart_id: ctx.params[:cart_id] } }

  # Step 3: Create order
  step :create_order,
       with: Order::CreateService,
       input: ->(ctx) {
         {
           cart_id: ctx.params[:cart_id],
           shipping_address: ctx.params[:shipping_address]
         }
       }

  # Step 4: Charge payment
  step :charge_payment,
       with: Payment::ChargeService,
       input: ->(ctx) {
         {
           order_id: ctx.create_order.id,
           amount: ctx.calculate_total.final_total,
           payment_method: ctx.params[:payment_method]
         }
       },
       rollback: ->(ctx) {
         # Refund payment if later steps fail
         Payment::RefundService.new(ctx.user, params: {
           payment_id: ctx.charge_payment.id
         }).call if ctx.charge_payment
       }

  # Step 5: Reserve inventory
  step :reserve_inventory,
       with: Inventory::ReserveService,
       input: ->(ctx) { { order_id: ctx.create_order.id } },
       rollback: ->(ctx) {
         # Release inventory if later steps fail
         Inventory::ReleaseService.new(ctx.user, params: {
           order_id: ctx.create_order.id
         }).call if ctx.create_order
       }

  # Step 6: Update order status
  step :confirm_order,
       with: Order::ConfirmService,
       input: ->(ctx) {
         {
           order_id: ctx.create_order.id,
           payment_id: ctx.charge_payment.id
         }
       }

  # Step 7: Send confirmation email (optional)
  step :send_confirmation,
       with: Email::OrderConfirmationService,
       input: ->(ctx) { { order_id: ctx.create_order.id } },
       optional: true

  # Step 8: Notify admin for large orders (optional, conditional)
  step :notify_admin,
       with: Admin::NotifyLargeOrderService,
       input: ->(ctx) { { order_id: ctx.create_order.id } },
       optional: true,
       if: ->(ctx) { ctx.calculate_total.final_total > 1000 }

  private

  def validate_cart(context)
    cart = Cart.find(context.params[:cart_id])
    context.fail!("Cart is empty") if cart.empty?
  end

  def clear_cart_on_success(context)
    if context.success?
      cart = Cart.find(context.params[:cart_id])
      cart.clear!
    end
  end
end
```

---

## Controllers

### ProductsController

```ruby
# app/controllers/products_controller.rb
class ProductsController < ApplicationController
  before_action :authenticate_user!, except: [:index, :show]

  def index
    result = Product::IndexService.new(current_user, params: index_params).call
    render json: result
  end

  def show
    result = Product::ShowService.new(current_user, params: { id: params[:id] }).call
    render json: result

  rescue BetterService::Errors::Runtime::ResourceNotFoundError => e
    render json: { error: "Product not found" }, status: :not_found
  end

  def create
    result = Product::CreateService.new(current_user, params: product_params).call
    render json: result, status: :created

  rescue BetterService::Errors::Runtime::ValidationError => e
    render json: {
      error: e.message,
      errors: e.context[:validation_errors]
    }, status: :unprocessable_entity

  rescue BetterService::Errors::Runtime::AuthorizationError => e
    render json: { error: e.message }, status: :forbidden
  end

  private

  def index_params
    params.permit(:category, :search, :min_price, :max_price, :page, :per_page)
  end

  def product_params
    params.require(:product).permit(:name, :sku, :price, :stock, :description, :category, :published)
  end
end
```

---

### CartsController

```ruby
# app/controllers/carts_controller.rb
class CartsController < ApplicationController
  before_action :authenticate_user!

  def show
    cart = current_user.cart || current_user.create_cart!
    render json: {
      items: cart.cart_items.includes(:product),
      total: cart.total,
      count: cart.cart_items.count
    }
  end

  def add_item
    result = Cart::AddItemService.new(current_user, params: add_item_params).call
    render json: result

  rescue BetterService::Errors::Runtime::ExecutionError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def remove_item
    result = Cart::RemoveItemService.new(current_user, params: { cart_item_id: params[:id] }).call
    render json: result
  end

  private

  def add_item_params
    params.require(:cart).permit(:product_id, :quantity)
  end
end
```

---

### OrdersController

```ruby
# app/controllers/orders_controller.rb
class OrdersController < ApplicationController
  before_action :authenticate_user!

  def index
    result = Order::IndexService.new(current_user, params: index_params).call
    render json: result
  end

  def show
    result = Order::ShowService.new(current_user, params: { id: params[:id] }).call
    render json: result
  end

  def checkout
    result = Order::CheckoutWorkflow.new(current_user, params: checkout_params).call

    if result[:success]
      render json: {
        order: result[:context].create_order,
        payment: result[:context].charge_payment
      }, status: :created
    else
      render json: {
        error: "Checkout failed",
        failed_step: result[:metadata][:failed_step]
      }, status: :unprocessable_entity
    end

  rescue BetterService::Errors::Runtime::ValidationError => e
    render json: {
      error: e.message,
      errors: e.context[:validation_errors]
    }, status: :unprocessable_entity
  end

  private

  def checkout_params
    params.require(:order).permit(
      :cart_id,
      :payment_method,
      :coupon_code,
      shipping_address: [:street, :city, :state, :zip]
    )
  end
end
```

---

## Testing

### Testing Checkout Workflow

```ruby
# test/workflows/order/checkout_workflow_test.rb
require "test_helper"

class Order::CheckoutWorkflowTest < ActiveSupport::TestCase
  setup do
    @user = users(:customer)
    @cart = carts(:user_cart)
    @cart.cart_items.create!(product: products(:laptop), quantity: 1)

    @valid_params = {
      cart_id: @cart.id,
      payment_method: "card_123",
      shipping_address: {
        street: "123 Main St",
        city: "New York",
        state: "NY",
        zip: "10001"
      }
    }
  end

  test "completes checkout successfully" do
    result = Order::CheckoutWorkflow.new(@user, params: @valid_params).call

    assert result[:success]
    assert result[:context].create_order.present?
    assert result[:context].charge_payment.present?
    assert_equal "confirmed", result[:context].create_order.status
    assert @cart.reload.empty?
  end

  test "rolls back on payment failure" do
    # Stub payment service to fail
    Payment::ChargeService.stub :call, -> { raise "Payment declined" } do
      result = Order::CheckoutWorkflow.new(@user, params: @valid_params).call

      assert result[:failure?]
      assert_equal :charge_payment, result[:metadata][:failed_step]
      assert_equal 0, Order.where(user: @user).count
    end
  end

  test "rolls back on inventory failure" do
    # Set product stock to 0
    products(:laptop).update!(stock: 0)

    result = Order::CheckoutWorkflow.new(@user, params: @valid_params).call

    assert result[:failure?]
    assert_equal 0, Order.where(user: @user).count
  end
end
```

---

## Summary

This complete e-commerce example demonstrates:

✅ **Product Management** - CRUD with authorization and caching
✅ **Shopping Cart** - Add/remove items with stock validation
✅ **Checkout Workflow** - Multi-step process with rollback
✅ **Payment Integration** - Charging and refunding
✅ **Inventory Management** - Stock reservation and release
✅ **Order Processing** - Order creation and confirmation
✅ **Error Handling** - Comprehensive exception handling
✅ **Testing** - Full test coverage

---

## Next Steps

- **[Getting Started](../start/getting-started.md)** - Build your first service
- **[Workflows](../workflows/01_workflows_introduction.md)** - Learn more about workflows
- **[Testing Guide](../testing.md)** - Test your services

---

**See Also:**
- [Service Types](../services/01_services_structure.md)
- [Error Handling](../advanced/error-handling.md)
- [Cache Invalidation](../advanced/cache-invalidation.md)
