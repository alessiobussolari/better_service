# frozen_string_literal: true

class PaymentRepository < BetterService::Repository::BaseRepository
  # Custom scopes
  def by_order(order)
    model.where(order: order)
  end

  def by_status(status)
    model.where(status: status)
  end

  def by_provider(provider)
    model.where(provider: provider)
  end

  def successful
    by_status(:completed)
  end

  def pending
    by_status(:pending)
  end

  def failed
    by_status(:failed)
  end

  def refunded
    by_status(:refunded)
  end

  def find_by_transaction_id(transaction_id)
    model.find_by(transaction_id: transaction_id)
  end

  def with_order
    model.includes(:order)
  end
end
