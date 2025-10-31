# frozen_string_literal: true

class Product::DestroyService < BetterService::DestroyService
  # Schema for validating params
  schema do
    required(:id).filled
  end

  # Phase 1: Search - Load the resource
  search_with do
    { resource: user.products.find(params[:id]) }
  end

  # Phase 2: Process - Delete the resource
  process_with do |data|
    product = data[:resource]
    product.destroy!
    { resource: product }
  end

  # Phase 4: Respond - Format response (optional override)
  respond_with do |data|
    success_result("Product deleted successfully", data)
  end
end
