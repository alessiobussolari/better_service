# frozen_string_literal: true

class Notification::OrderConfirmationService < Notification::BaseService
  performed_action :sent

  schema do
    required(:order_id).filled(:integer)
    required(:email).filled(:string)
  end

  search_with do
    order = Order.includes(:order_items, :payment).find(params[:order_id])
    { order: order }
  rescue ActiveRecord::RecordNotFound
    raise BetterService::Errors::Runtime::ResourceNotFoundError.new(
      "Order not found",
      context: { id: params[:order_id] }
    )
  end

  process_with do |data|
    order = data[:order]

    # Simulate sending email (in real app would use ActionMailer)
    notification = {
      type: :email,
      to: params[:email],
      subject: "Order Confirmation ##{order.id}",
      body: "Thank you for your order! Total: $#{order.total}",
      sent_at: Time.current
    }

    { resource: { order: order, notification: notification } }
  end

  respond_with do |data|
    success_result(message("order_confirmation.success", email: params[:email]), data)
  end
end
