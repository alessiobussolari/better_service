# frozen_string_literal: true

class Payment::Paypal::ChargeService < Payment::BaseService
  performed_action :charged
  with_transaction true
  auto_invalidate_cache true

  schema do
    required(:payment_id).filled(:integer)
    optional(:paypal_order_id).maybe(:string)
  end

  authorize_with do
    payment = Payment.find_by(id: params[:payment_id])
    next false unless payment

    user.admin? || payment.order.user_id == user.id
  end

  search_with do
    payment = payment_repository.with_order.find(params[:payment_id])

    unless payment.paypal?
      raise BetterService::Errors::Runtime::ExecutionError.new(
        message("paypal.wrong_provider"),
        context: { provider: payment.provider }
      )
    end

    { resource: payment }
  rescue ActiveRecord::RecordNotFound
    raise BetterService::Errors::Runtime::ResourceNotFoundError.new(
      "Payment not found",
      context: { id: params[:payment_id] }
    )
  end

  process_with do |data|
    payment = data[:resource]

    unless payment.processing?
      raise BetterService::Errors::Runtime::ExecutionError.new(
        message("paypal.not_processing"),
        context: { status: payment.status }
      )
    end

    # Simulate PayPal capture
    paypal_capture_id = "PAY-#{SecureRandom.hex(16).upcase}"

    payment_repository.update!(payment,
      status: :completed,
      transaction_id: paypal_capture_id,
      completed_at: Time.current
    )

    # Note: Order status is updated by Order::ConfirmService in the workflow

    {
      resource: payment.reload,
      paypal_capture_id: paypal_capture_id,
      provider: "paypal"
    }
  rescue ActiveRecord::RecordInvalid => e
    raise BetterService::Errors::Runtime::DatabaseError.new(
      "Failed to charge via PayPal",
      context: { errors: e.record.errors.to_hash },
      original_error: e
    )
  end

  respond_with do |data|
    success_result(message("paypal.capture_success", capture_id: data[:paypal_capture_id]), data)
  end
end
