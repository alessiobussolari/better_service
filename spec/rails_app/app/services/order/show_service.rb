# frozen_string_literal: true

class Order::ShowService < Order::BaseService
  performed_action :showed

  presenter OrderPresenter

  schema do
    required(:id).filled(:integer)
  end

  authorize_with do
    # Admin can view any order (even non-existent - will get "not found" error)
    next true if user.admin?

    order = Order.find_by(id: params[:id])
    next false unless order

    # Owner can view their own orders
    order.user_id == user.id
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
    { resource: data[:resource] }
  end

  respond_with do |data|
    success_result(message("show.success"), data)
  end
end
