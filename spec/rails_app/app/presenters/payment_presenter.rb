# frozen_string_literal: true

class PaymentPresenter < BetterService::Presenter
  def as_json(opts = {})
    {
      id: object.id,
      amount: formatted_amount,
      status: object.status,
      provider: object.provider,
      transaction_id: object.transaction_id,
      created_at: object.created_at&.iso8601
    }.tap do |json|
      json[:order_id] = object.order_id if include_field?(:order)
      json[:can_refund] = object.refundable? if current_user&.admin?
      json[:metadata] = object.metadata_hash if include_field?(:metadata) && current_user&.admin?
    end
  end

  private

  def formatted_amount
    "$#{'%.2f' % object.amount}" if object.amount
  end
end
