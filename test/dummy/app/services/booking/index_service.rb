# frozen_string_literal: true

module Booking
  class IndexService < BetterService::Services::IndexService
    # Schema validation for params
    schema do
      optional(:page).filled(:integer, gteq?: 1)
      optional(:search).maybe(:string)
    end

    # DSL-based implementation
    search_with do
      bookings = user.bookings
      bookings = bookings.where("title LIKE ?", "%#{params[:search]}%") if params[:search].present?
      bookings = bookings.page(params[:page]) if params[:page].present?

      { items: bookings.to_a }
    end

    process_with do |data|
      {
        items: data[:items],
        metadata: {
          stats: {
            total: data[:items].count
          },
          pagination: {
            page: params[:page] || 1,
            total: user.bookings.count
          }
        }
      }
    end

    respond_with do |data|
      success_result(message("bookings.loaded"), data)
    end

    # Optional viewer for UI config
    viewer do |processed, transformed, result|
      {
        page_title: "My Bookings",
        breadcrumbs: [
          { label: "Home", url: "/" },
          { label: "Bookings", url: "/bookings" }
        ],
        actions: [:create_booking]
      }
    end
  end
end
