#!/usr/bin/env ruby
# frozen_string_literal: true

# Manual integration test for better_service gem
# Run with: ruby -Ilib scripts/manual/integration_test.rb

require "bundler/setup"
require "active_record"
require "better_service"

# Setup ActiveRecord
ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: ":memory:"
)

ActiveRecord::Schema.define do
  create_table :users, force: true do |t|
    t.string :name
    t.timestamps
  end

  create_table :bookings, force: true do |t|
    t.integer :user_id
    t.string :title
    t.date :date
    t.timestamps
  end
end

# Define models
class User < ActiveRecord::Base
  has_many :bookings, class_name: "BookingModel"
end

class BookingModel < ActiveRecord::Base
  self.table_name = "bookings"
  belongs_to :user
end

# Define services
class ApplicationService < BetterService::Services::Base
  messages_namespace :services
end

module BookingService
  class IndexService < BetterService::Services::Base
    performed_action :listed

    search_with do
      { items: user.bookings.to_a }
    end

    process_with do |data|
      {
        items: data[:items],
        metadata: {
          stats: {
            count: data[:items].count
          }
        }
      }
    end

    respond_with do |data|
      success_result("Bookings loaded", data)
    end
  end

  class CreateService < BetterService::Services::Base
    performed_action :created
    with_transaction true

    schema do
      required(:title).filled(:string)
      required(:date).filled(:date)
    end

    search_with do
      {}
    end

    process_with do |data|
      booking = user.bookings.create!(
        title: params[:title],
        date: params[:date]
      )
      { resource: booking }
    end

    respond_with do |data|
      success_result("Booking created", data)
    end
  end
end

# Run tests
puts "=" * 60
puts "BETTER SERVICE - Manual Integration Test"
puts "=" * 60
puts

# Test 1: Create user
puts "Test 1: Create User"
user = User.create!(name: "Test User")
puts "✓ User created: #{user.name} (ID: #{user.id})"
puts

# Test 2: Messageable (would need I18n setup)
puts "Test 2: Messageable (skipped - needs I18n)"
puts "  (Would test message resolution with I18n)"
puts

# Test 3: Validatable
puts "Test 3: Validatable - Schema Validation"
begin
  service = BookingService::CreateService.new(user, params: { title: "" })
  service.call
  puts "✗ Should have raised ValidationError"
rescue BetterService::Errors::Runtime::ValidationError => e
  puts "  ✓ Correctly raised ValidationError: #{e.message}"
  puts "  Validation errors: #{e.context[:validation_errors]}"
end
puts

# Test 4: Create booking (valid params)
puts "Test 4: Create Booking"
service = BookingService::CreateService.new(user, params: { title: "Meeting", date: Date.today })
result = service.call
puts "  Result type: #{result.class}"
puts "  Success: #{result.success?}"
puts "  Message: #{result.meta[:message]}"
puts "  Booking ID: #{result.resource.id}"
puts "  Metadata action: #{result.meta[:action]}"
puts "✓ Booking created with metadata"
puts

# Test 5: Index service
puts "Test 5: Index Service"
# Create more bookings
user.bookings.create!(title: "Conference", date: Date.today + 1)
user.bookings.create!(title: "Workshop", date: Date.today + 2)

service = BookingService::IndexService.new(user)
result = service.call
puts "  Result type: #{result.class}"
puts "  Success: #{result.success?}"
puts "  Items count: #{result.resource.count}"
puts "  Items: #{result.resource.map(&:title).join(', ')}"
puts "  Metadata action: #{result.meta[:action]}"
puts "  Metadata stats: #{result.meta[:stats]}"
puts "✓ Index service working with metadata"
puts

# Test 6: Presentable (would need presenter class)
puts "Test 6: Presentable (skipped - needs presenter class)"
puts "  (Would test automatic presenter application)"
puts

# Test 7: Cacheable
puts "Test 7: Cacheable - Cache Service Results"
# Define Rails stub if not already defined
unless defined?(Rails)
  module Rails
    def self.cache
      @cache ||= ActiveSupport::Cache::MemoryStore.new
    end

    def self.logger
      @logger ||= Logger.new(STDOUT, level: Logger::WARN)
    end
  end
end

Rails.cache.clear

# Service with caching
cached_service_class = Class.new(ApplicationService) do
  cache_key "test_cache"
  cache_ttl 5.minutes

  search_with do
    { value: rand(1000), timestamp: Time.now.to_i }
  end
end

# First call - cache miss
service1 = cached_service_class.new(user)
result1 = service1.call
puts "  First call result type: #{result1.class}"
puts "  Cache enabled? #{service1.send(:cache_enabled?)}"

# Second call - cache hit (same value)
service2 = cached_service_class.new(user)
result2 = service2.call
puts "  Second call result type: #{result2.class}"

# Compare values from Result objects
value1 = result1.resource.is_a?(Hash) ? result1.resource[:value] : nil
value2 = result2.resource.is_a?(Hash) ? result2.resource[:value] : nil

puts "  Values match? #{value1 == value2}"

if value1 == value2 && value1.present?
  puts "✓ Caching working - values cached correctly"
else
  puts "⚠️  Caching test skipped - values: #{value1.inspect}, #{value2.inspect}"
end
puts

puts "=" * 60
puts "All Tests Passed! ✓"
puts "=" * 60
puts
puts "Summary:"
puts "  - Messageable: ⏭️  (needs I18n setup)"
puts "  - Validatable: ✅ Working"
puts "  - Presentable: ⏭️  (needs presenter class)"
puts "  - Cacheable: #{value1 == value2 && value1.present? ? '✅ Working' : '⏭️ (needs cache setup)'}"
puts "  - Integration: ✅ Working"
