# frozen_string_literal: true

class Product::PublishService < BetterService::ActionService
  action_name :publish

  # Schema for validating params
  schema do
    required(:id).filled
    # Add your action-specific params here
  end

  # Phase 1: Search - Load the resource
  search_with do
    { resource: user.products.find(params[:id]) }
  end

  # Phase 2: Process - Perform the action
  process_with do |data|
    product = data[:resource]
    product.update!(published: true)
    { resource: product }
  end

  # Phase 4: Respond - Format response (optional override)
  respond_with do |data|
    success_result("Product publish successfully", data)
  end
end
