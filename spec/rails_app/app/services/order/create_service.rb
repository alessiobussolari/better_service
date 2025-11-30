# frozen_string_literal: true

class Order::CreateService < Order::BaseService
  performed_action :created
  with_transaction true
  auto_invalidate_cache true

  schema do
    required(:items).filled(:array, min_size?: 1).each do
      hash do
        required(:product_id).filled(:integer)
        required(:quantity).filled(:integer, gt?: 0)
      end
    end
    optional(:payment_method).maybe(:string, included_in?: %w[credit_card paypal bank_transfer])
  end

  search_with do
    # Validate all products exist and are published
    product_ids = params[:items].map { |item| item[:product_id] }
    products = Product.where(id: product_ids, published: true).index_by(&:id)

    missing = product_ids - products.keys
    if missing.any?
      raise BetterService::Errors::Runtime::ValidationError.new(
        "Some products are not available",
        context: { missing_product_ids: missing }
      )
    end

    { products: products }
  end

  process_with do |data|
    products = data[:products]

    # Calculate total
    total = params[:items].sum do |item|
      product = products[item[:product_id]]
      product.price * item[:quantity]
    end

    # Create order
    order = order_repository.create!(
      user: user,
      total: total,
      status: :pending,
      payment_method: params[:payment_method] || :credit_card
    )

    # Create order items
    params[:items].each do |item|
      product = products[item[:product_id]]
      order.order_items.create!(
        product: product,
        quantity: item[:quantity],
        unit_price: product.price
      )
    end

    { resource: order }
  rescue ActiveRecord::RecordInvalid => e
    raise BetterService::Errors::Runtime::DatabaseError.new(
      "Failed to create order",
      context: { errors: e.record.errors.to_hash },
      original_error: e
    )
  end

  respond_with do |data|
    success_result(message("create.success", id: data[:resource].id), data)
  end
end
