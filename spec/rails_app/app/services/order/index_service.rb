# frozen_string_literal: true

class Order::IndexService < Order::BaseService
  performed_action :listed

  cache_key "orders_index"
  cache_ttl 15.minutes
  presenter OrderPresenter

  schema do
    optional(:status).maybe(:string, included_in?: %w[pending confirmed paid shipped cancelled])
    optional(:page).filled(:integer, gteq?: 1)
    optional(:per_page).filled(:integer, gteq?: 1, lteq?: 50)
  end

  search_with do
    scope = order_repository.by_user(user)
    scope = scope.by_status(params[:status]) if params[:status].present?
    scope = scope.includes(:order_items, :payment)
    { items: scope.recent.to_a }
  end

  process_with do |data|
    {
      items: data[:items],
      metadata: {
        count: data[:items].size
      }
    }
  end

  respond_with do |data|
    success_result(message("index.success"), data)
  end
end
