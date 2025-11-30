# frozen_string_literal: true

class Order::CancelService < Order::BaseService
  performed_action :cancelled
  with_transaction true
  auto_invalidate_cache true

  schema do
    required(:id).filled(:integer)
    optional(:reason).maybe(:string, max_size?: 500)
  end

  authorize_with do
    order = Order.find_by(id: params[:id])
    next false unless order

    # Owner or admin can cancel
    user.admin? || order.user_id == user.id
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

    # Can only cancel pending or confirmed orders
    unless order.pending? || order.confirmed?
      raise BetterService::Errors::Runtime::ExecutionError.new(
        message("cancel.not_cancellable"),
        context: { id: order.id, status: order.status }
      )
    end

    order_repository.update!(order, status: :cancelled)

    # If there was a payment, mark it for refund
    if order.payment&.completed?
      order.payment.update!(status: :refunded)
    end

    { resource: order.reload, cancelled_at: Time.current }
  rescue ActiveRecord::RecordInvalid => e
    raise BetterService::Errors::Runtime::DatabaseError.new(
      "Failed to cancel order",
      context: { errors: e.record.errors.to_hash },
      original_error: e
    )
  end

  respond_with do |data|
    success_result(message("cancel.success", id: data[:resource].id), data)
  end
end
