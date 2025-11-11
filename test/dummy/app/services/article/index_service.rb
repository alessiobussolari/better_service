# frozen_string_literal: true

class Article::IndexService < BetterService::Services::IndexService
  # Schema for validating params
  schema do
    optional(:page).filled(:integer, gteq?: 1)
    optional(:per_page).filled(:integer, gteq?: 1, lteq?: 100)
    optional(:search).maybe(:string)
  end

  # Phase 1: Search - Load raw data
  search_with do
    articles = user.articles
    articles = articles.where("title LIKE ?", "%#{params[:search]}%") if params[:search].present?
    # Add pagination if needed (e.g., with Kaminari or Pagy)
    # articles = articles.page(params[:page]).per(params[:per_page] || 25)

    { items: articles.to_a }
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
    success_result("Articles loaded successfully", data)
  end

  # Phase 5: Viewer - UI configuration (optional)
  # viewer do |processed, transformed, result|
  #   {
  #     page_title: "Articles",
  #     breadcrumbs: [
  #       { label: "Home", url: "/" },
  #       { label: "Articles", url: "/articles" }
  #     ]
  #   }
  # end
end
