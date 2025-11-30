# frozen_string_literal: true

RSpec.shared_context "with user" do
  let(:user) { User.create!(name: "Test User", email: "test@example.com") }
  let(:admin_user) do
    User.create!(name: "Admin User", email: "admin@example.com", admin: true)
  end
  let(:seller_user) do
    User.create!(name: "Seller User", email: "seller@example.com", seller: true)
  end
end

RSpec.shared_context "with products" do
  include_context "with user"

  let(:product) do
    Product.create!(
      name: "Test Product",
      price: 99.99,
      user: seller_user,
      published: true,
      stock: 50
    )
  end

  let(:unpublished_product) do
    Product.create!(
      name: "Unpublished Product",
      price: 49.99,
      user: seller_user,
      published: false,
      stock: 30
    )
  end

  let(:out_of_stock_product) do
    Product.create!(
      name: "Out of Stock Product",
      price: 29.99,
      user: seller_user,
      published: true,
      stock: 0
    )
  end
end

RSpec.shared_context "with order" do
  include_context "with products"

  let(:order) do
    order = Order.create!(
      user: user,
      total: 199.98,
      status: :pending,
      payment_method: :credit_card
    )
    order.order_items.create!(
      product: product,
      quantity: 2,
      unit_price: product.price
    )
    order
  end

  let(:confirmed_order) do
    order = Order.create!(
      user: user,
      total: 99.99,
      status: :confirmed,
      payment_method: :paypal
    )
    order.order_items.create!(
      product: product,
      quantity: 1,
      unit_price: product.price
    )
    order
  end

  let(:paid_order) do
    order = Order.create!(
      user: user,
      total: 99.99,
      status: :paid,
      payment_method: :credit_card
    )
    order.order_items.create!(
      product: product,
      quantity: 1,
      unit_price: product.price
    )
    Payment.create!(
      order: order,
      amount: order.total,
      provider: :stripe,
      status: :completed,
      transaction_id: "ch_test123",
      completed_at: Time.current
    )
    order
  end
end

RSpec.shared_context "with payment" do
  include_context "with order"

  let(:pending_payment) do
    Payment.create!(
      order: order,
      amount: order.total,
      provider: :stripe,
      status: :pending
    )
  end

  let(:processing_payment) do
    Payment.create!(
      order: confirmed_order,
      amount: confirmed_order.total,
      provider: :stripe,
      status: :processing
    )
  end

  let(:completed_payment) do
    Payment.create!(
      order: paid_order,
      amount: paid_order.total,
      provider: :stripe,
      status: :completed,
      transaction_id: "ch_completed123",
      completed_at: Time.current
    )
  end
end
