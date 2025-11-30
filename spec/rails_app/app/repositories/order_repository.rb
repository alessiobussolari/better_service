# frozen_string_literal: true

class OrderRepository < BetterService::Repository::BaseRepository
  # Custom scopes
  def by_user(user)
    model.where(user: user)
  end

  def by_status(status)
    model.where(status: status)
  end

  def pending
    by_status(:pending)
  end

  def confirmed
    by_status(:confirmed)
  end

  def paid
    by_status(:paid)
  end

  def cancelled
    by_status(:cancelled)
  end

  def recent(limit = 10)
    model.order(created_at: :desc).limit(limit)
  end

  def with_items
    model.includes(:order_items)
  end

  def with_payment
    model.includes(:payment)
  end

  def full_details
    model.includes(:order_items, :payment, :user)
  end
end
