# frozen_string_literal: true

class Inventory::ReserveService < Inventory::BaseService
  performed_action :reserved
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
    reserved_items = []

    order.order_items.each do |item|
      product = item.product

      # Check stock (simulated - in real app would check inventory table)
      available_stock = product.stock || 100

      if item.quantity > available_stock
        raise BetterService::Errors::Runtime::ExecutionError.new(
          message("reserve.insufficient_stock"),
          context: {
            product_id: product.id,
            product_name: product.name,
            requested: item.quantity,
            available: available_stock
          }
        )
      end

      # Reserve stock (simulated)
      new_stock = available_stock - item.quantity
      product.update!(stock: new_stock)

      reserved_items << {
        product_id: product.id,
        quantity: item.quantity,
        previous_stock: available_stock,
        new_stock: new_stock
      }
    end

    { resource: { order: order, reserved_items: reserved_items }, reserved_items: reserved_items }
  rescue ActiveRecord::RecordInvalid => e
    raise BetterService::Errors::Runtime::DatabaseError.new(
      "Failed to reserve inventory",
      context: { errors: e.record.errors.to_hash },
      original_error: e
    )
  end

  respond_with do |data|
    success_result(message("reserve.success", count: data[:reserved_items].size), data)
  end
end
