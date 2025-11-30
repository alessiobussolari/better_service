# frozen_string_literal: true

class Payment::ProcessService < Payment::BaseService
  performed_action :processed
  with_transaction true
  auto_invalidate_cache true

  schema do
    required(:payment_id).filled(:integer)
  end

  authorize_with do
    # Admin can process any payment (even non-existent - will get "not found")
    next true if user.admin?

    payment = Payment.find_by(id: params[:payment_id])
    next false unless payment

    # Owner can process their own payment
    payment.order.user_id == user.id
  end

  search_with do
    payment = payment_repository.with_order.find(params[:payment_id])
    { resource: payment }
  rescue ActiveRecord::RecordNotFound
    raise BetterService::Errors::Runtime::ResourceNotFoundError.new(
      "Payment not found",
      context: { id: params[:payment_id] }
    )
  end

  process_with do |data|
    payment = data[:resource]

    unless payment.pending?
      raise BetterService::Errors::Runtime::ExecutionError.new(
        message("process.not_pending"),
        context: { id: payment.id, status: payment.status }
      )
    end

    # Mark as processing
    payment_repository.update!(payment, status: :processing)

    { resource: payment.reload }
  rescue ActiveRecord::RecordInvalid => e
    raise BetterService::Errors::Runtime::DatabaseError.new(
      "Failed to process payment",
      context: { errors: e.record.errors.to_hash },
      original_error: e
    )
  end

  respond_with do |data|
    success_result(message("process.success"), data)
  end
end
