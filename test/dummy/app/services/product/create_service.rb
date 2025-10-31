# frozen_string_literal: true

class Product::CreateService < BetterService::CreateService
  # Schema for validating params
  schema do
    required(:name).filled(:string)
    required(:price).filled(:decimal)
    optional(:published).filled(:bool)
  end

  # Phase 1: Search - Prepare dependencies (optional)
  search_with do
    {}
  end

  # Phase 2: Process - Create the resource
  process_with do |data|
    product = user.products.create!(params)
    { resource: product }
  end

  # Phase 4: Respond - Format response (optional override)
  respond_with do |data|
    success_result("Product created successfully", data)
  end
end
