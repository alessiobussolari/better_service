# Real-World Example

Complete e-commerce implementation using BetterService.

---

## Overview

### What We're Building

A complete order processing system.

```ruby
# Features:
# - Product catalog with inventory
# - Shopping cart management
# - Order creation with payment
# - Multiple payment methods (card, PayPal)
# - Email notifications
# - Inventory management
```

--------------------------------

## Models

### Database Schema

The models we're working with.

```ruby
# app/models/user.rb
class User < ApplicationRecord
  has_many :products
  has_many :orders
  has_one :cart

  def admin?
    role == "admin"
  end

  def seller?
    role == "seller"
  end
end

# app/models/product.rb
class Product < ApplicationRecord
  belongs_to :user
  has_many :cart_items
  has_many :order_items

  validates :name, :price, :stock, presence: true
  validates :price, numericality: { greater_than: 0 }
end

# app/models/cart.rb
class Cart < ApplicationRecord
  belongs_to :user
  has_many :cart_items, dependent: :destroy
  has_many :products, through: :cart_items

  def total
    cart_items.sum { |item| item.product.price * item.quantity }
  end
end

# app/models/order.rb
class Order < ApplicationRecord
  belongs_to :user
  has_many :order_items, dependent: :destroy

  enum status: { pending: 0, paid: 1, shipped: 2, completed: 3, cancelled: 4 }
end
```

--------------------------------

## Repositories

### ProductRepository

Product data access layer.

```ruby
# app/repositories/product_repository.rb
class ProductRepository < BetterService::Repositories::Base
  model Product

  def available
    scope.where("stock > 0")
  end

  def published
    scope.where(published: true)
  end

  def by_category(category)
    scope.where(category: category)
  end

  def low_stock(threshold: 10)
    scope.where("stock <= ?", threshold)
  end

  def decrement_stock!(product, quantity)
    product.with_lock do
      raise "Insufficient stock" if product.stock < quantity
      product.update!(stock: product.stock - quantity)
    end
  end

  def increment_stock!(product, quantity)
    product.with_lock do
      product.update!(stock: product.stock + quantity)
    end
  end
end
```

--------------------------------

### OrderRepository

Order data access layer.

```ruby
# app/repositories/order_repository.rb
class OrderRepository < BetterService::Repositories::Base
  model Order

  def by_user(user)
    scope.where(user: user)
  end

  def pending
    scope.where(status: :pending)
  end

  def recent(limit: 10)
    scope.order(created_at: :desc).limit(limit)
  end

  def with_items
    scope.includes(order_items: :product)
  end
end
```

--------------------------------

## Base Services

### Product::BaseService

Foundation for product services.

```ruby
# app/services/product/base_service.rb
class Product::BaseService < BetterService::Services::Base
  include BetterService::Concerns::Serviceable::RepositoryAware

  messages_namespace :products
  cache_contexts [:products]
  repository :product
end
```

--------------------------------

### Order::BaseService

Foundation for order services.

```ruby
# app/services/order/base_service.rb
class Order::BaseService < BetterService::Services::Base
  include BetterService::Concerns::Serviceable::RepositoryAware

  messages_namespace :orders
  repository :order
  repository :product
end
```

--------------------------------

## Product Services

### Product::CreateService

Create a new product.

```ruby
# app/services/product/create_service.rb
class Product::CreateService < Product::BaseService
  performed_action :created
  with_transaction true

  schema do
    required(:name).filled(:string, min_size?: 2, max_size?: 100)
    required(:price).filled(:decimal, gt?: 0)
    required(:stock).filled(:integer, gteq?: 0)
    optional(:description).filled(:string, max_size?: 5000)
    optional(:category).filled(:string)
  end

  authorize_with do
    next true if user.admin?
    user.seller?
  end

  process_with do
    product = product_repository.create!(
      name: params[:name],
      price: params[:price],
      stock: params[:stock],
      description: params[:description],
      category: params[:category],
      user: user,
      published: false
    )
    { resource: product }
  end

  respond_with do |data|
    success_result(message("create.success", name: data[:resource].name), data)
  end
end
```

--------------------------------

### Product::IndexService

List products with filtering.

```ruby
# app/services/product/index_service.rb
class Product::IndexService < Product::BaseService
  performed_action :listed

  schema do
    optional(:page).filled(:integer, gteq?: 1)
    optional(:per_page).filled(:integer, gteq?: 1, lteq?: 50)
    optional(:category).filled(:string)
    optional(:min_price).filled(:decimal, gteq?: 0)
    optional(:max_price).filled(:decimal, gt?: 0)
  end

  search_with do
    products = product_repository.published.available

    products = products.by_category(params[:category]) if params[:category]

    if params[:min_price] && params[:max_price]
      products = products.where(price: params[:min_price]..params[:max_price])
    end

    page = params[:page] || 1
    per_page = params[:per_page] || 20
    products = products.page(page).per(per_page)

    {
      items: products.to_a,
      total: products.total_count,
      page: page,
      total_pages: products.total_pages
    }
  end

  respond_with do |data|
    success_result(message("index.success"), data)
  end
end
```

--------------------------------

## Cart Services

### Cart::AddItemService

Add item to cart.

```ruby
# app/services/cart/add_item_service.rb
class Cart::AddItemService < BetterService::Services::Base
  include BetterService::Concerns::Serviceable::RepositoryAware

  performed_action :item_added
  with_transaction true
  repository :product

  schema do
    required(:product_id).filled(:integer)
    required(:quantity).filled(:integer, gt?: 0, lteq?: 10)
  end

  authorize_with do
    user.present?
  end

  search_with do
    product = product_repository.find(params[:product_id])
    cart = user.cart || user.create_cart!
    { product: product, cart: cart }
  end

  process_with do |data|
    product = data[:product]
    cart = data[:cart]

    if product.stock < params[:quantity]
      raise BetterService::Errors::Runtime::ExecutionError.new(
        "Insufficient stock",
        context: { available: product.stock, requested: params[:quantity] }
      )
    end

    cart_item = cart.cart_items.find_or_initialize_by(product: product)
    cart_item.quantity = (cart_item.quantity || 0) + params[:quantity]
    cart_item.save!

    { resource: cart.reload }
  end

  respond_with do |data|
    success_result("Item added to cart", data)
  end
end
```

--------------------------------

## Payment Services

### Payment::CardService

Process credit card payment.

```ruby
# app/services/payment/card_service.rb
class Payment::CardService < BetterService::Services::Base
  performed_action :charged
  with_transaction true

  schema do
    required(:order_id).filled(:integer)
    required(:card_token).filled(:string)
  end

  authorize_with do
    next true if user.admin?

    order = Order.find_by(id: params[:order_id])
    next false unless order

    order.user_id == user.id
  end

  search_with do
    order = Order.find(params[:order_id])
    { order: order }
  end

  process_with do |data|
    order = data[:order]

    # Call payment gateway (Stripe, etc.)
    charge = PaymentGateway.charge(
      amount: order.total,
      currency: "USD",
      card_token: params[:card_token],
      description: "Order ##{order.id}"
    )

    unless charge.success?
      raise BetterService::Errors::Runtime::ExecutionError.new(
        "Payment failed: #{charge.error_message}",
        context: { order_id: order.id }
      )
    end

    order.update!(
      status: :paid,
      payment_method: "credit_card",
      payment_id: charge.id,
      paid_at: Time.current
    )

    { resource: order, charge: charge }
  end

  respond_with do |data|
    success_result("Payment processed successfully", data)
  end
end
```

--------------------------------

### Payment::PaypalService

Process PayPal payment.

```ruby
# app/services/payment/paypal_service.rb
class Payment::PaypalService < BetterService::Services::Base
  performed_action :charged
  with_transaction true

  schema do
    required(:order_id).filled(:integer)
    required(:paypal_order_id).filled(:string)
  end

  authorize_with do
    next true if user.admin?

    order = Order.find_by(id: params[:order_id])
    order&.user_id == user.id
  end

  search_with do
    order = Order.find(params[:order_id])
    { order: order }
  end

  process_with do |data|
    order = data[:order]

    # Capture PayPal payment
    capture = PaypalGateway.capture(params[:paypal_order_id])

    unless capture.success?
      raise BetterService::Errors::Runtime::ExecutionError.new(
        "PayPal payment failed",
        context: { error: capture.error }
      )
    end

    order.update!(
      status: :paid,
      payment_method: "paypal",
      payment_id: capture.id,
      paid_at: Time.current
    )

    { resource: order, capture: capture }
  end

  respond_with do |data|
    success_result("PayPal payment captured", data)
  end
end
```

--------------------------------

## Checkout Workflow

### Complete Checkout Flow

Full checkout with branching payment.

```ruby
# app/workflows/order/checkout_workflow.rb
class Order::CheckoutWorkflow < BetterService::Workflows::Base
  with_transaction true

  # Step 1: Validate cart
  step :validate_cart,
       with: Cart::ValidateService,
       input: ->(ctx) { { cart_id: ctx.user.cart&.id } }

  # Step 2: Check inventory for all items
  step :check_inventory,
       with: Inventory::CheckService,
       input: ->(ctx) { { cart: ctx.validate_cart } }

  # Step 3: Create the order
  step :create_order,
       with: Order::CreateFromCartService,
       input: ->(ctx) {
         {
           cart: ctx.validate_cart,
           payment_method: ctx.payment_method
         }
       }

  # Step 4: Process payment (branched by method)
  branch do
    on ->(ctx) { ctx.payment_method == "credit_card" } do
      step :charge_card,
           with: Payment::CardService,
           input: ->(ctx) {
             {
               order_id: ctx.create_order.id,
               card_token: ctx.card_token
             }
           },
           rollback: ->(ctx) {
             Payment::RefundService.new(ctx.user, params: {
               charge_id: ctx.charge_card[:charge].id
             }).call
           }
    end

    on ->(ctx) { ctx.payment_method == "paypal" } do
      step :charge_paypal,
           with: Payment::PaypalService,
           input: ->(ctx) {
             {
               order_id: ctx.create_order.id,
               paypal_order_id: ctx.paypal_order_id
             }
           },
           rollback: ->(ctx) {
             Payment::PaypalRefundService.new(ctx.user, params: {
               capture_id: ctx.charge_paypal[:capture].id
             }).call
           }
    end
  end

  # Step 5: Reserve inventory
  step :reserve_inventory,
       with: Inventory::ReserveService,
       input: ->(ctx) { { order: ctx.create_order } },
       rollback: ->(ctx) {
         Inventory::ReleaseService.new(ctx.user, params: {
           order_id: ctx.create_order.id
         }).call
       }

  # Step 6: Clear the cart
  step :clear_cart,
       with: Cart::ClearService,
       input: ->(ctx) { { cart_id: ctx.validate_cart.id } }

  # Step 7: Send confirmation email (optional)
  step :send_confirmation,
       with: Email::OrderConfirmationService,
       input: ->(ctx) { { order: ctx.create_order } },
       optional: true
end
```

--------------------------------

## Controller Integration

### OrdersController

Wire everything together.

```ruby
# app/controllers/orders_controller.rb
class OrdersController < ApplicationController
  before_action :authenticate_user!

  def checkout
    result = Order::CheckoutWorkflow.new(
      current_user,
      params: checkout_params
    ).call

    if result[:success]
      order = result[:context].create_order
      render json: {
        order: order,
        message: "Order placed successfully"
      }, status: :created
    end
  rescue BetterService::Errors::Runtime::ValidationError => e
    render json: {
      error: "Invalid checkout data",
      errors: e.context[:validation_errors]
    }, status: :unprocessable_entity
  rescue BetterService::Errors::Runtime::ExecutionError => e
    render json: {
      error: e.message,
      details: e.context
    }, status: :unprocessable_entity
  rescue BetterService::Errors::Workflowable::Runtime::StepExecutionError => e
    render json: {
      error: "Checkout failed",
      step: e.context[:step],
      details: e.message
    }, status: :unprocessable_entity
  end

  private

  def checkout_params
    params.permit(
      :payment_method,
      :card_token,
      :paypal_order_id
    ).to_h.symbolize_keys
  end
end
```

--------------------------------

## Testing the System

### Integration Test

Test the complete checkout flow.

```ruby
# test/workflows/order/checkout_workflow_test.rb
class Order::CheckoutWorkflowTest < ActiveSupport::TestCase
  setup do
    @user = users(:buyer)
    @product = products(:widget)
    @cart = @user.create_cart!
    @cart.cart_items.create!(product: @product, quantity: 2)
  end

  test "successful credit card checkout" do
    PaymentGateway.stubs(:charge).returns(
      OpenStruct.new(success?: true, id: "ch_123")
    )

    result = Order::CheckoutWorkflow.new(
      @user,
      params: {
        payment_method: "credit_card",
        card_token: "tok_valid"
      }
    ).call

    assert result[:success]

    order = result[:context].create_order
    assert_equal :paid, order.status.to_sym
    assert_equal "credit_card", order.payment_method
    assert_equal 2, order.order_items.first.quantity

    # Verify inventory decremented
    assert_equal @product.stock - 2, @product.reload.stock

    # Verify cart cleared
    assert_equal 0, @cart.reload.cart_items.count
  end

  test "rolls back on payment failure" do
    PaymentGateway.stubs(:charge).returns(
      OpenStruct.new(success?: false, error_message: "Card declined")
    )

    initial_stock = @product.stock

    assert_raises(BetterService::Errors::Workflowable::Runtime::StepExecutionError) do
      Order::CheckoutWorkflow.new(
        @user,
        params: {
          payment_method: "credit_card",
          card_token: "tok_invalid"
        }
      ).call
    end

    # Verify no order created (transaction rolled back)
    assert_equal 0, Order.where(user: @user).count

    # Verify inventory unchanged
    assert_equal initial_stock, @product.reload.stock

    # Verify cart still has items
    assert_equal 1, @cart.reload.cart_items.count
  end
end
```

--------------------------------

## Summary

### Key Patterns Used

Patterns demonstrated in this example.

```ruby
# 1. BaseService per resource with repository
class Product::BaseService < BetterService::Services::Base
  repository :product
end

# 2. Workflow for multi-step operations
class Order::CheckoutWorkflow < BetterService::Workflows::Base
  step :validate, with: ValidateService
  step :process, with: ProcessService
end

# 3. Branching for conditional logic
branch do
  on ->(ctx) { condition } do
    step :path_a, with: ServiceA
  end
  otherwise do
    step :path_b, with: ServiceB
  end
end

# 4. Rollback for compensation
step :charge,
     with: PaymentService,
     rollback: ->(ctx) { RefundService.new(...).call }

# 5. Optional steps for non-critical operations
step :notify, with: EmailService, optional: true
```

--------------------------------
