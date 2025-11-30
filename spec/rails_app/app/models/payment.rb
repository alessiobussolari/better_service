# frozen_string_literal: true

class Payment < ApplicationRecord
  belongs_to :order

  enum :status, {
    pending: 0,
    processing: 1,
    completed: 2,
    failed: 3,
    refunded: 4
  }

  enum :provider, {
    stripe: 0,
    paypal: 1,
    bank: 2
  }

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :status, presence: true
  validates :provider, presence: true

  # Scopes
  scope :successful, -> { where(status: :completed) }
  scope :by_provider, ->(provider) { where(provider: provider) }

  # Check if payment can be refunded
  def refundable?
    completed?
  end

  # Store metadata as JSON
  def metadata_hash
    return {} if metadata.blank?

    JSON.parse(metadata)
  rescue JSON::ParserError
    {}
  end

  def metadata_hash=(hash)
    self.metadata = hash.to_json
  end

  # Generate transaction ID if not provided
  before_create :generate_transaction_id, unless: :transaction_id?

  private

  def generate_transaction_id
    self.transaction_id = "TXN-#{SecureRandom.hex(8).upcase}"
  end
end
