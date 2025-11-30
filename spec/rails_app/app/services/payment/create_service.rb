# frozen_string_literal: true

class Payment::CreateService < Payment::BaseService
  performed_action :created
  with_transaction true
  auto_invalidate_cache true

  schema do
    required(:order_id).filled(:integer)
    required(:provider).filled(:string, included_in?: %w[stripe paypal bank])
  end

  authorize_with do
    order = Order.find_by(id: params[:order_id])
    next false unless order

    # Owner or admin can create payment
    user.admin? || order.user_id == user.id
  end

  search_with do
    order = Order.includes(:payment).find(params[:order_id])

    if order.payment.present?
      raise BetterService::Errors::Runtime::ExecutionError.new(
        message("create.already_exists"),
        context: { order_id: order.id, payment_id: order.payment.id }
      )
    end

    { order: order }
  rescue ActiveRecord::RecordNotFound
    raise BetterService::Errors::Runtime::ResourceNotFoundError.new(
      "Order not found",
      context: { id: params[:order_id] }
    )
  end

  process_with do |data|
    order = data[:order]

    payment = payment_repository.create!(
      order: order,
      amount: order.total,
      provider: params[:provider],
      status: :pending
    )

    { resource: payment, order: order }
  rescue ActiveRecord::RecordInvalid => e
    raise BetterService::Errors::Runtime::DatabaseError.new(
      "Failed to create payment",
      context: { errors: e.record.errors.to_hash },
      original_error: e
    )
  end

  respond_with do |data|
    success_result(message("create.success", provider: data[:resource].provider), data)
  end
end
