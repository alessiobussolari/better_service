# frozen_string_literal: true

class Product::ShowService < Product::BaseService
  performed_action :showed

  presenter ProductPresenter

  schema do
    required(:id).filled(:integer)
  end

  authorize_with do
    # Admin can view any product (even non-existent - will get "not found" error)
    next true if user.admin?

    product = Product.find_by(id: params[:id])
    next false unless product

    # Public products can be viewed by anyone
    # Unpublished products can only be viewed by owner
    product.published? || product.user_id == user.id
  end

  search_with do
    product = product_repository.find(params[:id])
    { resource: product }
  rescue ActiveRecord::RecordNotFound
    raise BetterService::Errors::Runtime::ResourceNotFoundError.new(
      "Product not found",
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
