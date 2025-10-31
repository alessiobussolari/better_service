# frozen_string_literal: true

class User < ApplicationRecord
  has_many :bookings, dependent: :destroy
  has_many :products, dependent: :destroy

  validates :name, presence: true
end
