# frozen_string_literal: true

class Inventory::ReleaseService < Inventory::BaseService
  performed_action :released
  with_transaction true
  auto_invalidate_cache true

  schema do
    required(:order_id).filled(:integer)
  end

  search_with do
    order = Order.includes(order_items: :product).find(params[:order_id])
    { order: order }
  rescue ActiveRecord::RecordNotFound
    raise BetterService::Errors::Runtime::ResourceNotFoundError.new(
      "Order not found",
      context: { id: params[:order_id] }
    )
  end

  process_with do |data|
    order = data[:order]
    released_items = []

    order.order_items.each do |item|
      product = item.product
      next unless product

      # Release reserved stock
      current_stock = product.stock || 0
      new_stock = current_stock + item.quantity
      product.update!(stock: new_stock)

      released_items << {
        product_id: product.id,
        quantity: item.quantity,
        previous_stock: current_stock,
        new_stock: new_stock
      }
    end

    { resource: { order: order, released_items: released_items }, released_items: released_items }
  rescue ActiveRecord::RecordInvalid => e
    raise BetterService::Errors::Runtime::DatabaseError.new(
      "Failed to release inventory",
      context: { errors: e.record.errors.to_hash },
      original_error: e
    )
  end

  respond_with do |data|
    success_result(message("release.success", count: data[:released_items].size), data)
  end
end
