# frozen_string_literal: true

class Order::ShipService < Order::BaseService
  performed_action :shipped
  with_transaction true
  auto_invalidate_cache true

  schema do
    required(:id).filled(:integer)
    optional(:tracking_number).maybe(:string)
    optional(:carrier).maybe(:string, included_in?: %w[fedex ups dhl usps])
  end

  authorize_with do
    # Only admin can ship orders
    user.admin?
  end

  search_with do
    order = order_repository.full_details.find(params[:id])
    { resource: order }
  rescue ActiveRecord::RecordNotFound
    raise BetterService::Errors::Runtime::ResourceNotFoundError.new(
      "Order not found",
      context: { id: params[:id] }
    )
  end

  process_with do |data|
    order = data[:resource]

    # Must be paid to ship
    unless order.paid?
      raise BetterService::Errors::Runtime::ExecutionError.new(
        message("ship.not_paid"),
        context: { id: order.id, status: order.status }
      )
    end

    order_repository.update!(order, status: :shipped)

    {
      resource: order.reload,
      metadata: {
        shipping_info: {
          tracking_number: params[:tracking_number],
          carrier: params[:carrier],
          shipped_at: Time.current
        }
      }
    }
  rescue ActiveRecord::RecordInvalid => e
    raise BetterService::Errors::Runtime::DatabaseError.new(
      "Failed to ship order",
      context: { errors: e.record.errors.to_hash },
      original_error: e
    )
  end

  respond_with do |data|
    success_result(message("ship.success", id: data[:resource].id), data)
  end
end
