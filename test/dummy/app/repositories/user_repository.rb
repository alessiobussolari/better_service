# frozen_string_literal: true

class UserRepository < BetterService::Repository::BaseRepository
  def initialize
    super(User)
  end

  # Eager load products association
  def with_products
    model.includes(:products)
  end

  # Eager load bookings association
  def with_bookings
    model.includes(:bookings)
  end

  # Eager load all associations
  def with_all_associations
    model.includes(:products, :bookings)
  end

  # Find user by email
  def find_by_email(email)
    find_by(email: email)
  end
end
