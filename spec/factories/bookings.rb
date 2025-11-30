# frozen_string_literal: true

FactoryBot.define do
  factory :booking do
    association :user
    sequence(:title) { |n| "Booking #{n}" }
    date { Date.current + 1.week }
    description { "Test booking description" }

    trait :past do
      date { Date.current - 1.week }
    end

    trait :future do
      date { Date.current + 1.month }
    end

    trait :today do
      date { Date.current }
    end
  end
end
