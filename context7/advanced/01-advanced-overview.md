# Advanced Features Overview

Overview of advanced BetterService features for production applications including instrumentation, monitoring, and observability.

## Instrumentation & Events

ActiveSupport::Notifications integration for service lifecycle tracking.

```ruby
# BetterService automatically publishes events during execution
class Product::CreateService < BetterService::CreateService
  schema do
    required(:name).filled(:string)
    required(:price).filled(:integer, gt?: 0)
  end

  process_with do
    product = user.products.create!(params)
    { resource: product }
  end
end

# Events published automatically:
# - service.started (when service begins)
# - service.completed (on success)
# - service.failed (on error)
# - cache.hit / cache.miss (if caching enabled)

# Subscribe to events
ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
  puts "Service #{payload[:service_name]} completed in #{payload[:duration]}ms"
end

# Call service - events published automatically
Product::CreateService.new(user, params: { name: "Widget", price: 100 }).call
# => Prints: "Service Product::CreateService completed in 45.2ms"
```

## Built-in StatsSubscriber

Automatic statistics collection for all services.

```ruby
# Enable in initializer
BetterService.configure do |config|
  config.stats_subscriber_enabled = true
end

# Execute some services
Product::CreateService.new(user, params: { name: "A", price: 10 }).call
Product::CreateService.new(user, params: { name: "B", price: 20 }).call
Product::IndexService.new(user, params: {}).call

# Access collected statistics
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
#   "Product::IndexService" => { ... }
# }

# Get summary across all services
summary = BetterService::Subscribers::StatsSubscriber.summary
# => {
#   total_services: 2,
#   total_executions: 3,
#   total_successes: 3,
#   total_failures: 0,
#   success_rate: 100.0,
#   avg_duration: 35.5,
#   cache_hit_rate: 0
# }
```

## Built-in LogSubscriber

Automatic logging of service events to Rails.logger.

```ruby
# Enable in initializer
BetterService.configure do |config|
  config.log_subscriber_enabled = true
end

# Call service
Product::CreateService.new(user, params: { name: "Widget", price: 100 }).call

# Logs automatically written:
# [BetterService] Product::CreateService started (user: 123)
# [BetterService] Product::CreateService completed in 45.2ms (user: 123)

# On error:
# [BetterService] ERROR: Product::CreateService failed in 12.4ms (user: 123)
# Error: ActiveRecord::RecordInvalid - Validation failed: Name can't be blank
```

## Configuration Options

Control instrumentation behavior and privacy.

```ruby
# config/initializers/better_service.rb
BetterService.configure do |config|
  # Master switch for instrumentation
  config.instrumentation_enabled = true  # default: true

  # Include service params in event payloads
  config.instrumentation_include_args = true  # default: true

  # Include service results in completed events
  config.instrumentation_include_result = false  # default: false

  # Exclude specific services from instrumentation
  config.instrumentation_excluded_services = [
    "HealthCheckService",
    "Internal::StatusService"
  ]

  # Enable built-in subscribers
  config.stats_subscriber_enabled = true   # default: true
  config.log_subscriber_enabled = true     # default: true
end
```

## Custom Subscribers

Create your own subscribers for custom metrics, alerts, or integrations.

```ruby
# app/subscribers/performance_monitor.rb
class PerformanceMonitor
  SLOW_THRESHOLD = 1000 # milliseconds

  def self.attach
    ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
      duration = payload[:duration]
      service_name = payload[:service_name]

      if duration > SLOW_THRESHOLD
        SlackNotifier.alert(
          "Slow service detected: #{service_name} took #{duration}ms"
        )
      end
    end
  end
end

# In initializer
PerformanceMonitor.attach
```

## Cache Events

Track cache effectiveness with automatic cache events.

```ruby
class Product::IndexService < BetterService::IndexService
  cache_key "products"
  cache_ttl 15.minutes

  schema do
    optional(:category).filled(:string)
  end

  search_with do
    user.products.where(category: params[:category])
  end
end

# Subscribe to cache events
ActiveSupport::Notifications.subscribe("cache.hit") do |name, start, finish, id, payload|
  puts "Cache HIT for #{payload[:service_name]}"
end

ActiveSupport::Notifications.subscribe("cache.miss") do |name, start, finish, id, payload|
  puts "Cache MISS for #{payload[:service_name]}"
end

# First call - cache miss
Product::IndexService.new(user, params: { category: "electronics" }).call
# => Prints: "Cache MISS for Product::IndexService"

# Second call - cache hit
Product::IndexService.new(user, params: { category: "electronics" }).call
# => Prints: "Cache HIT for Product::IndexService"
```

## Error Tracking

Automatically track errors and error types.

```ruby
# Subscribe to failures
ActiveSupport::Notifications.subscribe("service.failed") do |name, start, finish, id, payload|
  ErrorTracker.report(
    error_class: payload[:error_class],
    error_message: payload[:error_message],
    service: payload[:service_name],
    user_id: payload[:user_id],
    duration: payload[:duration],
    backtrace: payload[:error_backtrace]
  )
end

# Errors automatically tracked when services fail
begin
  Product::CreateService.new(user, params: { name: "", price: -10 }).call
rescue BetterService::Errors::Runtime::DatabaseError => e
  # Error already tracked by subscriber
  # Handle error in application
end
```

## Security & Privacy

Protect sensitive data in instrumentation.

```ruby
# ❌ WRONG: May expose passwords, tokens, credit cards
BetterService.configure do |config|
  config.instrumentation_include_args = true
  config.instrumentation_include_result = true
end

# ✅ CORRECT: Exclude sensitive services
BetterService.configure do |config|
  config.instrumentation_excluded_services = [
    "Authentication::LoginService",
    "Payment::ProcessService",
    "User::ChangePasswordService"
  ]
end

# ✅ CORRECT: Sanitize params in custom subscriber
ActiveSupport::Notifications.subscribe("service.started") do |*args|
  payload = args[4]
  safe_params = payload[:params]&.except(:password, :token, :credit_card)
  Metrics.track(service: payload[:service_name], params: safe_params)
end
```

## See Also

- **Instrumentation best practices**: `/context7/examples/03-best-practices.md` - Best practices for monitoring services
- **Full documentation**: `/docs/advanced/instrumentation.md` - Complete instrumentation guide with configuration, payload details, and subscriber API
- **More examples**: Browse other files in `/context7/advanced/` for specific instrumentation patterns
