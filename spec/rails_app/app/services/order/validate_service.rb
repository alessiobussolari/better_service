# frozen_string_literal: true

class Order::ValidateService < Order::BaseService
  performed_action :validated

  schema do
    required(:id).filled(:integer)
  end

  authorize_with do
    # Admin can validate any order (even non-existent - will get "not found")
    next true if user.admin?

    order = Order.find_by(id: params[:id])
    next false unless order

    # Owner can validate their own orders
    order.user_id == user.id
  end

  search_with do
    order = order_repository.with_items.find(params[:id])
    { resource: order }
  rescue ActiveRecord::RecordNotFound
    raise BetterService::Errors::Runtime::ResourceNotFoundError.new(
      "Order not found",
      context: { id: params[:id] }
    )
  end

  process_with do |data|
    order = data[:resource]

    # Validate order is in a valid state for checkout
    unless order.pending?
      raise BetterService::Errors::Runtime::ExecutionError.new(
        message("validate.invalid"),
        context: { id: order.id, status: order.status }
      )
    end

    # Validate order has items
    if order.order_items.empty?
      raise BetterService::Errors::Runtime::ValidationError.new(
        "Order has no items",
        context: { id: order.id }
      )
    end

    # Validate all products are still available
    order.order_items.each do |item|
      unless item.product&.published?
        raise BetterService::Errors::Runtime::ValidationError.new(
          "Product #{item.product&.name || 'unknown'} is no longer available",
          context: { product_id: item.product_id }
        )
      end
    end

    { resource: order }
  end

  respond_with do |data|
    success_result(message("validate.success"), data)
  end
end
