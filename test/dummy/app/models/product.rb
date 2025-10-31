# frozen_string_literal: true

class Product < ApplicationRecord
  validates :name, presence: true
  validates :price, presence: true, numericality: { greater_than: 0 }

  belongs_to :user

  scope :published, -> { where(published: true) }
  scope :unpublished, -> { where(published: false) }
end
