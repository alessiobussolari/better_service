# frozen_string_literal: true

class OrderItemRepository < BetterService::Repository::BaseRepository
  # Custom scopes
  def by_order(order)
    model.where(order: order)
  end

  def by_product(product)
    model.where(product: product)
  end

  def with_product
    model.includes(:product)
  end
end
