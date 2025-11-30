# frozen_string_literal: true

class Product::CreateService < Product::BaseService
  performed_action :created
  with_transaction true
  auto_invalidate_cache true

  schema do
    required(:name).filled(:string, min_size?: 2)
    required(:price).filled(:decimal, gt?: 0)
    optional(:published).maybe(:bool)
  end

  authorize_with do
    user.admin? || user.seller?
  end

  search_with do
    {}
  end

  process_with do |_data|
    product = product_repository.create!(
      name: params[:name],
      price: params[:price],
      published: params[:published] || false,
      user: user
    )
    { resource: product }
  rescue ActiveRecord::RecordInvalid => e
    raise BetterService::Errors::Runtime::DatabaseError.new(
      "Failed to create product",
      context: { errors: e.record.errors.to_hash },
      original_error: e
    )
  end

  respond_with do |data|
    success_result(message("create.success", name: data[:resource].name), data)
  end
end
