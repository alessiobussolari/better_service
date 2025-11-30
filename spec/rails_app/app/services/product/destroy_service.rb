# frozen_string_literal: true

class Product::DestroyService < Product::BaseService
  performed_action :destroyed
  with_transaction true
  auto_invalidate_cache true

  schema do
    required(:id).filled(:integer)
  end

  authorize_with do
    # Admin or owner can delete products
    # Owner check needs to happen after search (done in process_with)
    # So authorize_with always passes - detailed auth is in process_with
    true
  end

  # Additional authorization after search
  def authorize_owner?(product)
    user.admin? || product.user_id == user.id
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

    # Check owner authorization
    unless authorize_owner?(product)
      raise BetterService::Errors::Runtime::AuthorizationError.new(
        "Not authorized to delete this product",
        context: { user_id: user.id, product_owner_id: product.user_id }
      )
    end

    product_repository.destroy!(product)
    { resource: product }
  rescue ActiveRecord::RecordNotDestroyed => e
    raise BetterService::Errors::Runtime::DatabaseError.new(
      "Failed to delete product",
      context: { id: params[:id] },
      original_error: e
    )
  end

  respond_with do |data|
    success_result(message("destroy.success"), data)
  end
end
