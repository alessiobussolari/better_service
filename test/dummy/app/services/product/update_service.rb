# frozen_string_literal: true

class Product::UpdateService < BetterService::UpdateService
  # Schema for validating params
  schema do
    required(:id).filled
    # Add your optional attributes here
  end

  # Phase 1: Search - Load the resource
  search_with do
    { resource: user.products.find(params[:id]) }
  end

  # Phase 2: Process - Update the resource
  process_with do |data|
    product = data[:resource]
    product.update!(params.except(:id))
    { resource: product }
  end

  # Phase 4: Respond - Format response (optional override)
  respond_with do |data|
    success_result("Product updated successfully", data)
  end
end
