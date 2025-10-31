# frozen_string_literal: true

class Product::IndexService < BetterService::IndexService
  # Schema for validating params
  schema do
    optional(:page).filled(:integer, gteq?: 1)
    optional(:per_page).filled(:integer, gteq?: 1, lteq?: 100)
    optional(:search).maybe(:string)
  end

  # Phase 1: Search - Load raw data
  search_with do
    products = user.products
    products = products.where("name LIKE ?", "%#{params[:search]}%") if params[:search].present?
    # Add pagination if needed (e.g., with Kaminari or Pagy)
    # products = products.page(params[:page]).per(params[:per_page] || 25)

    { items: products.to_a }
  end

  # Phase 2: Process - Transform and aggregate data
  process_with do |data|
    {
      items: data[:items],
      metadata: {
        stats: {
          total: data[:items].count
        },
        pagination: {
          page: params[:page] || 1,
          per_page: params[:per_page] || 25
        }
      }
    }
  end

  # Phase 4: Respond - Format response (optional override)
  respond_with do |data|
    success_result("Products loaded successfully", data)
  end

  # Phase 5: Viewer - UI configuration (optional)
  # viewer do |processed, transformed, result|
  #   {
  #     page_title: "Products",
  #     breadcrumbs: [
  #       { label: "Home", url: "/" },
  #       { label: "Products", url: "/products" }
  #     ]
  #   }
  # end
end
