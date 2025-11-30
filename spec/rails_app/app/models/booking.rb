# frozen_string_literal: true

class Booking < ApplicationRecord
  belongs_to :user

  validates :title, presence: true
  validates :date, presence: true
end
