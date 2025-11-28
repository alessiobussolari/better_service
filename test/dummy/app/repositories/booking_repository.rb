# frozen_string_literal: true

class BookingRepository < BetterService::Repository::BaseRepository
  def initialize
    super(Booking)
  end

  # Returns bookings with date >= today
  def upcoming
    model.where("date >= ?", Date.current)
  end

  # Returns bookings with date < today
  def past
    model.where("date < ?", Date.current)
  end

  # Filter bookings by user_id
  def by_user(user_id)
    where(user_id: user_id)
  end

  # Find bookings for a specific date
  def for_date(date)
    where(date: date)
  end
end
