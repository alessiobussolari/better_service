# frozen_string_literal: true

class Order < ApplicationRecord
  belongs_to :user
  has_many :order_items, dependent: :destroy
  has_one :payment, dependent: :destroy

  enum :status, {
    pending: 0,
    confirmed: 1,
    paid: 2,
    shipped: 3,
    cancelled: 4
  }

  enum :payment_method, {
    credit_card: 0,
    paypal: 1,
    bank_transfer: 2
  }

  validates :total, presence: true, numericality: { greater_than: 0 }
  validates :status, presence: true
  validates :payment_method, presence: true

  # Scopes
  scope :by_status, ->(status) { where(status: status) }
  scope :by_user, ->(user) { where(user: user) }
  scope :recent, -> { order(created_at: :desc) }

  # Calculate total from items
  def calculate_total
    order_items.sum { |item| item.quantity * item.unit_price }
  end

  # Check if order can be cancelled
  def cancellable?
    pending? || confirmed?
  end

  # Check if order can proceed to checkout
  def checkable?
    pending? && order_items.any?
  end
end
