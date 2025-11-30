# frozen_string_literal: true

class OrderPresenter < BetterService::Presenter
  def as_json(opts = {})
    {
      id: object.id,
      total: object.total,
      formatted_total: formatted_total,
      status: object.status,
      payment_method: object.payment_method,
      items_count: object.order_items.size,
      created_at: object.created_at&.iso8601
    }.tap do |json|
      json[:items] = items_info if include_field?(:items)
      json[:payment] = payment_info if include_field?(:payment) && object.payment
      json[:customer] = customer_info if current_user&.admin?
      json[:can_cancel] = object.cancellable? if current_user
    end
  end

  private

  def formatted_total
    "$#{object.total}" if object.total
  end

  def items_info
    object.order_items.map do |item|
      {
        id: item.id,
        product_id: item.product_id,
        product_name: item.product&.name,
        quantity: item.quantity,
        unit_price: "$#{item.unit_price}",
        line_total: "$#{item.line_total}"
      }
    end
  end

  def payment_info
    return nil unless object.payment

    {
      id: object.payment.id,
      status: object.payment.status,
      provider: object.payment.provider,
      transaction_id: object.payment.transaction_id
    }
  end

  def customer_info
    return nil unless object.user

    {
      id: object.user_id,
      name: object.user.name,
      email: object.user.email
    }
  end
end
