# frozen_string_literal: true

class Order::ConfirmService < Order::BaseService
  performed_action :confirmed
  with_transaction true
  auto_invalidate_cache true

  schema do
    required(:id).filled(:integer)
  end

  authorize_with do
    order = Order.find_by(id: params[:id])
    next false unless order

    # Only admin can confirm orders
    user.admin?
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

    unless order.pending?
      raise BetterService::Errors::Runtime::ExecutionError.new(
        message("confirm.not_pending"),
        context: { id: order.id, status: order.status }
      )
    end

    order_repository.update!(order, status: :confirmed)
    { resource: order.reload }
  rescue ActiveRecord::RecordInvalid => e
    raise BetterService::Errors::Runtime::DatabaseError.new(
      "Failed to confirm order",
      context: { errors: e.record.errors.to_hash },
      original_error: e
    )
  end

  respond_with do |data|
    success_result(message("confirm.success", id: data[:resource].id), data)
  end
end
