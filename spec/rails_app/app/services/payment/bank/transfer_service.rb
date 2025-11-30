# frozen_string_literal: true

class Payment::Bank::TransferService < Payment::BaseService
  performed_action :transferred
  with_transaction true
  auto_invalidate_cache true

  schema do
    required(:payment_id).filled(:integer)
    optional(:reference_number).maybe(:string)
  end

  authorize_with do
    # Only admin can confirm bank transfers
    user.admin?
  end

  search_with do
    payment = payment_repository.with_order.find(params[:payment_id])

    unless payment.bank?
      raise BetterService::Errors::Runtime::ExecutionError.new(
        message("bank.wrong_provider"),
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
        message("bank.not_processing"),
        context: { status: payment.status }
      )
    end

    # Bank transfer reference
    bank_reference = params[:reference_number] || "BT-#{SecureRandom.hex(8).upcase}"

    payment_repository.update!(payment,
      status: :completed,
      transaction_id: bank_reference,
      completed_at: Time.current
    )

    # Note: Order status is updated by Order::ConfirmService in the workflow

    {
      resource: payment.reload,
      bank_reference: bank_reference,
      provider: "bank"
    }
  rescue ActiveRecord::RecordInvalid => e
    raise BetterService::Errors::Runtime::DatabaseError.new(
      "Failed to confirm bank transfer",
      context: { errors: e.record.errors.to_hash },
      original_error: e
    )
  end

  respond_with do |data|
    success_result(message("bank.transfer_success", reference: data[:bank_reference]), data)
  end
end
