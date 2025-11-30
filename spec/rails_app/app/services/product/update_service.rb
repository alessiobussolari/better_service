# frozen_string_literal: true

class Product::UpdateService < Product::BaseService
  performed_action :updated
  with_transaction true
  auto_invalidate_cache true

  schema do
    required(:id).filled(:integer)
    optional(:name).filled(:string, min_size?: 2)
    optional(:price).filled(:decimal, gt?: 0)
    optional(:published).maybe(:bool)
  end

  authorize_with do
    # Admin can update any product (even non-existent - will get "not found" error)
    next true if user.admin?

    product = Product.find_by(id: params[:id])
    next false unless product

    # Owner can update their own products
    product.user_id == user.id
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
    product = data[:resource]
    update_params = params.except(:id).compact
    product_repository.update!(product, update_params)
    { resource: product.reload }
  rescue ActiveRecord::RecordInvalid => e
    raise BetterService::Errors::Runtime::DatabaseError.new(
      "Failed to update product",
      context: { errors: e.record.errors.to_hash },
      original_error: e
    )
  end

  respond_with do |data|
    success_result(message("update.success"), data)
  end
end
