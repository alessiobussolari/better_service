# StatsSubscriber Examples

Examples of using the built-in StatsSubscriber for metrics collection and analysis.

## Basic Statistics Access

Get execution statistics for all services.

```ruby
# Enable StatsSubscriber in initializer
BetterService.configure do |config|
  config.stats_subscriber_enabled = true
end

# Execute some services
Product::CreateService.new(user, params: { name: "Widget", price: 100 }).call
Product::CreateService.new(user, params: { name: "Gadget", price: 200 }).call
Product::IndexService.new(user, params: {}).call

# Access all statistics
stats = BetterService::Subscribers::StatsSubscriber.stats
# => {
#   "Product::CreateService" => {
#     executions: 2,
#     successes: 2,
#     failures: 0,
#     total_duration: 90.5,
#     avg_duration: 45.25,
#     cache_hits: 0,
#     cache_misses: 0,
#     errors: {}
#   },
#   "Product::IndexService" => {
#     executions: 1,
#     successes: 1,
#     failures: 0,
#     total_duration: 120.3,
#     avg_duration: 120.3,
#     cache_hits: 0,
#     cache_misses: 0,
#     errors: {}
#   }
# }
```

## Service-Specific Statistics

Get statistics for a single service.

```ruby
# Execute service multiple times
5.times do
  Product::CreateService.new(user, params: { name: "Item #{rand(100)}", price: rand(10..100) }).call
end

# Get stats for specific service
service_stats = BetterService::Subscribers::StatsSubscriber.stats_for("Product::CreateService")
# => {
#   executions: 5,
#   successes: 5,
#   failures: 0,
#   total_duration: 225.5,
#   avg_duration: 45.1,
#   cache_hits: 0,
#   cache_misses: 0,
#   errors: {}
# }

# Check if service is slow
if service_stats[:avg_duration] > 100
  puts "WARNING: Product::CreateService is running slow (avg: #{service_stats[:avg_duration]}ms)"
end
```

## Aggregate Summary

Get summary statistics across all services.

```ruby
# Execute various services
Product::IndexService.new(user, params: {}).call
Product::CreateService.new(user, params: { name: "A", price: 10 }).call
Product::UpdateService.new(user, params: { id: 1, name: "B" }).call
Product::DestroyService.new(user, params: { id: 1 }).call

# Get aggregate summary
summary = BetterService::Subscribers::StatsSubscriber.summary
# => {
#   total_services: 4,
#   total_executions: 4,
#   total_successes: 4,
#   total_failures: 0,
#   success_rate: 100.0,
#   avg_duration: 62.5,
#   cache_hit_rate: 0
# }

# Display summary
puts "Total Services: #{summary[:total_services]}"
puts "Success Rate: #{summary[:success_rate]}%"
puts "Average Duration: #{summary[:avg_duration]}ms"
```

## Error Tracking

Track errors and error types across services.

```ruby
# Execute services with some failures
begin
  Product::CreateService.new(user, params: { name: "", price: 100 }).call
rescue BetterService::Errors::Runtime::DatabaseError
  # Caught
end

begin
  Product::ShowService.new(user, params: { id: 99999 }).call
rescue BetterService::Errors::Runtime::ResourceNotFoundError
  # Caught
end

begin
  Product::CreateService.new(user, params: { name: "", price: -10 }).call
rescue BetterService::Errors::Runtime::DatabaseError
  # Caught
end

# Check error statistics
create_stats = BetterService::Subscribers::StatsSubscriber.stats_for("Product::CreateService")
# => {
#   executions: 2,
#   successes: 0,
#   failures: 2,
#   total_duration: 25.5,
#   avg_duration: 12.75,
#   cache_hits: 0,
#   cache_misses: 0,
#   errors: {
#     "ActiveRecord::RecordInvalid" => 2
#   }
# }

# Most common error for this service
most_common_error = create_stats[:errors].max_by { |k, v| v }
# => ["ActiveRecord::RecordInvalid", 2]
```

## Cache Statistics

Track cache hit/miss rates for cached services.

```ruby
class Product::IndexService < BetterService::IndexService
  cache_key "products"
  cache_ttl 15.minutes

  search_with do
    user.products.all
  end
end

# First calls - cache misses
3.times { Product::IndexService.new(user, params: {}).call }

# Subsequent calls - cache hits
7.times { Product::IndexService.new(user, params: {}).call }

# Check cache statistics
index_stats = BetterService::Subscribers::StatsSubscriber.stats_for("Product::IndexService")
# => {
#   executions: 10,
#   successes: 10,
#   failures: 0,
#   total_duration: 450.5,
#   avg_duration: 45.05,
#   cache_hits: 7,
#   cache_misses: 3,
#   errors: {}
# }

# Calculate cache hit rate
cache_total = index_stats[:cache_hits] + index_stats[:cache_misses]
cache_hit_rate = (index_stats[:cache_hits].to_f / cache_total * 100).round(2)
# => 70.0

puts "Cache hit rate: #{cache_hit_rate}%"
```

## Reset Statistics

Reset statistics for fresh collection period.

```ruby
# Execute services
Product::CreateService.new(user, params: { name: "A", price: 10 }).call
Product::IndexService.new(user, params: {}).call

# Stats are collected
stats = BetterService::Subscribers::StatsSubscriber.stats
stats.keys  # => ["Product::CreateService", "Product::IndexService"]

# Reset all statistics
BetterService::Subscribers::StatsSubscriber.reset!

# Stats cleared
stats = BetterService::Subscribers::StatsSubscriber.stats
stats  # => {}

# New executions start fresh tracking
Product::CreateService.new(user, params: { name: "B", price: 20 }).call

stats = BetterService::Subscribers::StatsSubscriber.stats
# => {
#   "Product::CreateService" => {
#     executions: 1,  # Reset counter
#     successes: 1,
#     ...
#   }
# }
```

## Periodic Statistics Reporting

Schedule periodic statistics reports.

```ruby
# In a background job or scheduled task
class StatisticsReportJob
  def perform
    summary = BetterService::Subscribers::StatsSubscriber.summary
    all_stats = BetterService::Subscribers::StatsSubscriber.stats

    # Send summary email
    StatsMailer.daily_summary(
      total_executions: summary[:total_executions],
      success_rate: summary[:success_rate],
      avg_duration: summary[:avg_duration]
    ).deliver_later

    # Log slow services
    slow_services = all_stats.select { |name, stats| stats[:avg_duration] > 1000 }
    if slow_services.any?
      Rails.logger.warn "Slow services detected: #{slow_services.keys.join(', ')}"
    end

    # Log high error rate services
    error_services = all_stats.select do |name, stats|
      stats[:executions] > 10 && (stats[:failures].to_f / stats[:executions]) > 0.05
    end

    if error_services.any?
      Rails.logger.error "High error rate services: #{error_services.keys.join(', ')}"
    end

    # Reset for next period
    BetterService::Subscribers::StatsSubscriber.reset!
  end
end

# Schedule daily at midnight
# In config/schedule.rb (if using whenever gem)
every 1.day, at: '0:00 am' do
  runner "StatisticsReportJob.perform"
end
```

## Dashboard Endpoint

Create an API endpoint for real-time statistics.

```ruby
# app/controllers/admin/stats_controller.rb
class Admin::StatsController < ApplicationController
  def index
    @summary = BetterService::Subscribers::StatsSubscriber.summary
    @all_stats = BetterService::Subscribers::StatsSubscriber.stats

    render json: {
      summary: @summary,
      services: @all_stats
    }
  end

  def service
    service_name = params[:name]
    stats = BetterService::Subscribers::StatsSubscriber.stats_for(service_name)

    if stats
      render json: { service: service_name, stats: stats }
    else
      render json: { error: "Service not found" }, status: :not_found
    end
  end

  def reset
    BetterService::Subscribers::StatsSubscriber.reset!
    render json: { message: "Statistics reset successfully" }
  end
end

# config/routes.rb
namespace :admin do
  get 'stats', to: 'stats#index'
  get 'stats/:name', to: 'stats#service'
  post 'stats/reset', to: 'stats#reset'
end

# Usage:
# GET /admin/stats
# => { summary: {...}, services: {...} }
#
# GET /admin/stats/Product::CreateService
# => { service: "Product::CreateService", stats: {...} }
#
# POST /admin/stats/reset
# => { message: "Statistics reset successfully" }
```

## Performance Comparison

Compare performance between services.

```ruby
# Execute multiple services
Product::CreateService.new(user, params: { name: "A", price: 10 }).call
Product::UpdateService.new(user, params: { id: 1, name: "B" }).call
Product::DestroyService.new(user, params: { id: 1 }).call
Product::IndexService.new(user, params: {}).call

# Get all stats
all_stats = BetterService::Subscribers::StatsSubscriber.stats

# Sort by average duration
sorted_by_duration = all_stats.sort_by { |name, stats| -stats[:avg_duration] }

puts "Slowest Services:"
sorted_by_duration.first(5).each do |name, stats|
  puts "  #{name}: #{stats[:avg_duration]}ms"
end

# Sort by failure rate
services_with_failures = all_stats.select { |name, stats| stats[:failures] > 0 }
sorted_by_failures = services_with_failures.sort_by do |name, stats|
  -(stats[:failures].to_f / stats[:executions])
end

puts "\nServices with Highest Failure Rate:"
sorted_by_failures.each do |name, stats|
  failure_rate = (stats[:failures].to_f / stats[:executions] * 100).round(2)
  puts "  #{name}: #{failure_rate}% (#{stats[:failures]}/#{stats[:executions]})"
end
```

## Alerting on Statistics

Set up alerts based on statistics thresholds.

```ruby
# In a monitoring job that runs periodically
class ServiceHealthMonitor
  SLOW_THRESHOLD = 1000      # ms
  ERROR_RATE_THRESHOLD = 0.05  # 5%
  CACHE_MISS_THRESHOLD = 0.3   # 30%

  def check
    all_stats = BetterService::Subscribers::StatsSubscriber.stats

    all_stats.each do |service_name, stats|
      # Alert on slow services
      if stats[:avg_duration] > SLOW_THRESHOLD
        alert(
          "Slow Service",
          "#{service_name} has average duration of #{stats[:avg_duration]}ms"
        )
      end

      # Alert on high error rate
      if stats[:executions] > 10
        error_rate = stats[:failures].to_f / stats[:executions]
        if error_rate > ERROR_RATE_THRESHOLD
          alert(
            "High Error Rate",
            "#{service_name} has #{(error_rate * 100).round(2)}% error rate"
          )
        end
      end

      # Alert on poor cache performance
      cache_total = stats[:cache_hits] + stats[:cache_misses]
      if cache_total > 10
        miss_rate = stats[:cache_misses].to_f / cache_total
        if miss_rate > CACHE_MISS_THRESHOLD
          alert(
            "Poor Cache Performance",
            "#{service_name} has #{(miss_rate * 100).round(2)}% cache miss rate"
          )
        end
      end
    end
  end

  private

  def alert(title, message)
    SlackNotifier.send(title: title, message: message)
    Rails.logger.warn "[ALERT] #{title}: #{message}"
  end
end
```
