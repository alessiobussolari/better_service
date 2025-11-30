# frozen_string_literal: true

class Product::IndexService < Product::BaseService
  performed_action :listed

  cache_key "products_index"
  cache_ttl 30.minutes
  presenter ProductPresenter

  schema do
    optional(:search).maybe(:string)
    optional(:page).filled(:integer, gteq?: 1)
    optional(:per_page).filled(:integer, gteq?: 1, lteq?: 100)
    optional(:published_only).maybe(:bool)
  end

  search_with do
    scope = product_repository.by_user(user.id)
    scope = scope.published if params[:published_only]
    scope = scope.where("name LIKE ?", "%#{params[:search]}%") if params[:search].present?
    { items: scope.to_a }
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
