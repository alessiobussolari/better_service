# frozen_string_literal: true

class Payment::Stripe::ChargeService < Payment::BaseService
  performed_action :charged
  with_transaction true
  auto_invalidate_cache true

  schema do
    required(:payment_id).filled(:integer)
    optional(:card_token).maybe(:string)
  end

  authorize_with do
    payment = Payment.find_by(id: params[:payment_id])
    next false unless payment

    user.admin? || payment.order.user_id == user.id
  end

  search_with do
    payment = payment_repository.with_order.find(params[:payment_id])

    unless payment.stripe?
      raise BetterService::Errors::Runtime::ExecutionError.new(
        message("stripe.wrong_provider"),
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
        message("stripe.not_processing"),
        context: { status: payment.status }
      )
    end

    # Simulate Stripe charge
    stripe_charge_id = "ch_#{SecureRandom.hex(12)}"

    payment_repository.update!(payment,
      status: :completed,
      transaction_id: stripe_charge_id,
      completed_at: Time.current
    )

    # Note: Order status is updated by Order::ConfirmService in the workflow

    {
      resource: payment.reload,
      stripe_charge_id: stripe_charge_id,
      provider: "stripe"
    }
  rescue ActiveRecord::RecordInvalid => e
    raise BetterService::Errors::Runtime::DatabaseError.new(
      "Failed to charge via Stripe",
      context: { errors: e.record.errors.to_hash },
      original_error: e
    )
  end

  respond_with do |data|
    success_result(message("stripe.charge_success", charge_id: data[:stripe_charge_id]), data)
  end
end
