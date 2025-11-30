# frozen_string_literal: true

FactoryBot.define do
  factory :product do
    association :user
    sequence(:name) { |n| "Product #{n}" }
    price { 99.99 }
    published { false }

    trait :published do
      published { true }
    end

    trait :unpublished do
      published { false }
    end

    trait :expensive do
      price { 999.99 }
    end

    trait :cheap do
      price { 9.99 }
    end
  end
end
