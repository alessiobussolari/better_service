# frozen_string_literal: true

class ProductRepository < BetterService::Repository::BaseRepository
  def initialize
    super(Product)
  end

  # Returns only published products
  def published
    model.published
  end

  # Returns only unpublished products
  def unpublished
    model.unpublished
  end

  # Filter products by user_id
  def by_user(user_id)
    where(user_id: user_id)
  end

  # Find products within a price range
  def in_price_range(min_price, max_price)
    model.where(price: min_price..max_price)
  end
end
