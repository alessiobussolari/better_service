# frozen_string_literal: true

class Product::PublishService < Product::BaseService
  performed_action :published
  with_transaction true
  auto_invalidate_cache true

  schema do
    required(:id).filled(:integer)
  end

  authorize_with do
    product = Product.find_by(id: params[:id])
    next false unless product

    # Owner or admin can publish
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

    if product.published?
      raise BetterService::Errors::Runtime::ExecutionError.new(
        message("publish.already_published"),
        context: { id: product.id }
      )
    end

    product_repository.update!(product, published: true)
    { resource: product.reload }
  end

  respond_with do |data|
    success_result(message("publish.success", name: data[:resource].name), data)
  end
end
