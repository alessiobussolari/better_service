# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:name) { |n| "User #{n}" }
    sequence(:email) { |n| "user#{n}@example.com" }

    trait :admin do
      # Add admin field if needed in the future
      # admin { true }
    end
  end
end
