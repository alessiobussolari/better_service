# frozen_string_literal: true

class Order::UpdateService < Order::BaseService
  performed_action :updated
  with_transaction true
  auto_invalidate_cache true

  schema do
    required(:id).filled(:integer)
    optional(:payment_method).maybe(:string, included_in?: %w[credit_card paypal bank_transfer])
  end

  authorize_with do
    order = Order.find_by(id: params[:id])
    next false unless order

    # Only owner can update, and only if pending
    order.user_id == user.id && order.pending?
  end

  search_with do
    order = order_repository.find(params[:id])
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
        message("update.not_pending"),
        context: { id: order.id, status: order.status }
      )
    end

    update_params = {}
    update_params[:payment_method] = params[:payment_method] if params[:payment_method].present?

    order_repository.update!(order, update_params) if update_params.any?
    { resource: order.reload }
  rescue ActiveRecord::RecordInvalid => e
    raise BetterService::Errors::Runtime::DatabaseError.new(
      "Failed to update order",
      context: { errors: e.record.errors.to_hash },
      original_error: e
    )
  end

  respond_with do |data|
    success_result(message("update.success", id: data[:resource].id), data)
  end
end
