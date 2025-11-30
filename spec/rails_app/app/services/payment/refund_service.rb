# frozen_string_literal: true

class Payment::RefundService < Payment::BaseService
  performed_action :refunded
  with_transaction true
  auto_invalidate_cache true

  schema do
    required(:payment_id).filled(:integer)
    optional(:reason).maybe(:string)
  end

  authorize_with do
    # Only admin can refund
    user.admin?
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

    unless payment.completed?
      raise BetterService::Errors::Runtime::ExecutionError.new(
        message("refund.not_completed"),
        context: { id: payment.id, status: payment.status }
      )
    end

    # Generate refund ID based on provider
    refund_id = case payment.provider
    when "stripe"
      "re_#{SecureRandom.hex(12)}"
    when "paypal"
      "REF-#{SecureRandom.hex(16).upcase}"
    else
      "RB-#{SecureRandom.hex(8).upcase}"
    end

    payment_repository.update!(payment,
      status: :refunded,
      refund_id: refund_id,
      refunded_at: Time.current
    )

    # Update order status
    payment.order.update!(status: :cancelled)

    {
      resource: payment.reload,
      refund_id: refund_id,
      reason: params[:reason]
    }
  rescue ActiveRecord::RecordInvalid => e
    raise BetterService::Errors::Runtime::DatabaseError.new(
      "Failed to refund payment",
      context: { errors: e.record.errors.to_hash },
      original_error: e
    )
  end

  respond_with do |data|
    success_result(message("refund.success", refund_id: data[:refund_id]), data)
  end
end
