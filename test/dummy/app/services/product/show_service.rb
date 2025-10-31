# frozen_string_literal: true

class Product::ShowService < BetterService::ShowService
  # Schema for validating params
  schema do
    required(:id).filled
  end

  # Phase 1: Search - Load the resource
  search_with do
    { resource: user.products.find(params[:id]) }
  end

  # Phase 2: Process - Transform data (optional)
  # process_with do |data|
  #   data
  # end

  # Phase 4: Respond - Format response (optional override)
  respond_with do |data|
    success_result("Product loaded successfully", data)
  end

  # Phase 5: Viewer - UI configuration (optional)
  # viewer do |processed, transformed, result|
  #   {
  #     page_title: "Product ##{result[:resource].id}",
  #     breadcrumbs: [
  #       { label: "Home", url: "/" },
  #       { label: "Products", url: "/products" },
  #       { label: "Show", url: "#" }
  #     ]
  #   }
  # end
end
