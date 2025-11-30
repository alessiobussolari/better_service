# frozen_string_literal: true

class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product

  validates :quantity, presence: true, numericality: { greater_than: 0, only_integer: true }
  validates :unit_price, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Calculate line total
  def line_total
    quantity * unit_price
  end

  # Set unit price from product if not provided
  before_validation :set_unit_price_from_product, on: :create

  private

  def set_unit_price_from_product
    self.unit_price ||= product&.price
  end
end
