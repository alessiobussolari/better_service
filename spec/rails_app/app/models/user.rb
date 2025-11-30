# frozen_string_literal: true

class User < ApplicationRecord
  has_many :bookings, dependent: :destroy
  has_many :products, dependent: :destroy
  has_many :orders, dependent: :destroy

  validates :name, presence: true

  # Role checks
  def admin?
    admin == true
  end

  def seller?
    seller == true
  end

  # Check if user can manage a resource
  def can_manage?(resource)
    return true if admin?
    return resource.user_id == id if resource.respond_to?(:user_id)

    false
  end
end
