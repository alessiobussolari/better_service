# frozen_string_literal: true

class Product < ApplicationRecord
  validates :name, presence: true
  validates :price, presence: true, numericality: { greater_than: 0 }
  validates :stock, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  belongs_to :user
  has_many :order_items, dependent: :restrict_with_error

  scope :published, -> { where(published: true) }
  scope :unpublished, -> { where(published: false) }
  scope :in_stock, -> { where("stock > 0") }

  def in_stock?
    (stock || 0) > 0
  end

  def available_stock
    stock || 0
  end
end
