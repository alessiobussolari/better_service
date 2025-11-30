# Configuration

Configure BetterService globally via initializer.

---

## Installation

### Generate Initializer

Create the configuration file.

```bash
rails g better_service:install
```

```ruby
# Creates config/initializers/better_service.rb
```

--------------------------------

## Configuration Options

### Full Configuration Example

Complete configuration with all options.

```ruby
BetterService.configure do |config|
  # ============================================
  # Instrumentation Settings
  # ============================================

  # Enable/disable all instrumentation events
  config.instrumentation_enabled = true

  # Include service arguments in event payloads (may expose sensitive data)
  config.instrumentation_include_args = false

  # Include service result in event payloads
  config.instrumentation_include_result = false

  # Exclude specific services from instrumentation
  config.instrumentation_excluded_services = [
    "HealthCheck::PingService",
    "Auth::TokenRefreshService"
  ]

  # ============================================
  # Subscriber Settings
  # ============================================

  # Enable built-in log subscriber
  config.log_subscriber_enabled = true

  # Log level for log subscriber (:debug, :info, :warn, :error)
  config.log_subscriber_level = :info

  # Enable built-in stats subscriber for metrics collection
  config.stats_subscriber_enabled = false

  # ============================================
  # Response Format
  # ============================================

  # Return BetterService::Result objects (recommended)
  # When false, returns [object, meta] tuples
  config.use_result_wrapper = true

  # ============================================
  # Cache Settings
  # ============================================

  # Define cache context dependencies for cascading invalidation
  config.cache_invalidation_map = {
    products: [:inventory, :reports, :homepage],
    orders: [:user_orders, :reports, :dashboard],
    users: [:user_profile, :user_orders]
  }
end
```

--------------------------------

## Instrumentation Events

### Available Events

Events published via ActiveSupport::Notifications.

```ruby
# Event                              | When                    | Payload
# -----------------------------------|-------------------------|---------------------------
# service.started.better_service    | Service call begins     | service, user_id, params
# service.completed.better_service  | Service succeeds        | service, user_id, duration, result
# service.failed.better_service     | Service fails           | service, user_id, duration, error
# cache.hit.better_service          | Cached result returned  | service, user_id, cache_key
# cache.miss.better_service         | Fresh execution needed  | service, user_id, cache_key
```

--------------------------------

## Custom Subscribers

### Subscribe to Events

Create custom event subscribers.

```ruby
# Custom subscriber
ActiveSupport::Notifications.subscribe("service.completed.better_service") do |name, start, finish, id, payload|
  duration_ms = (finish - start) * 1000

  Rails.logger.info({
    event: name,
    service: payload[:service],
    user_id: payload[:user_id],
    duration_ms: duration_ms.round(2),
    action: payload[:result]&.dig(:metadata, :action)
  }.to_json)
end

ActiveSupport::Notifications.subscribe("service.failed.better_service") do |name, start, finish, id, payload|
  Sentry.capture_message("Service failed", extra: {
    service: payload[:service],
    error: payload[:error].message,
    user_id: payload[:user_id]
  })
end
```

--------------------------------

## Built-in Log Subscriber

### LogSubscriber

Automatic service execution logging.

```ruby
# Enable in configuration
config.log_subscriber_enabled = true
config.log_subscriber_level = :info

# Output example:
# [BetterService] Product::CreateService completed in 45.23ms (action: created)
# [BetterService] Product::ShowService failed in 12.10ms (error: ResourceNotFoundError)
```

--------------------------------

## Built-in Stats Subscriber

### StatsSubscriber

Collect metrics for monitoring.

```ruby
# Enable in configuration
config.stats_subscriber_enabled = true

# Access collected stats
BetterService::Subscribers::StatsSubscriber.stats
# => {
#   "Product::CreateService" => {
#     calls: 150,
#     successes: 148,
#     failures: 2,
#     total_duration_ms: 6750.5,
#     avg_duration_ms: 45.0
#   }
# }
```

--------------------------------

## Datadog Subscriber Example

### Custom Monitoring Subscriber

Send metrics to Datadog.

```ruby
# config/initializers/better_service_monitoring.rb

class DatadogSubscriber
  def self.subscribe
    ActiveSupport::Notifications.subscribe(/\.better_service$/) do |name, start, finish, id, payload|
      event_type = name.split(".").first
      duration = (finish - start) * 1000

      tags = [
        "service:#{payload[:service]}",
        "event:#{event_type}"
      ]

      case event_type
      when "service.completed"
        Datadog::Statsd.increment("better_service.success", tags: tags)
        Datadog::Statsd.histogram("better_service.duration", duration, tags: tags)
      when "service.failed"
        Datadog::Statsd.increment("better_service.failure", tags: tags)
        Datadog::Statsd.histogram("better_service.duration", duration, tags: tags)
      when "cache.hit"
        Datadog::Statsd.increment("better_service.cache.hit", tags: tags)
      when "cache.miss"
        Datadog::Statsd.increment("better_service.cache.miss", tags: tags)
      end
    end
  end
end

DatadogSubscriber.subscribe if Rails.env.production?
```

--------------------------------

## Cache Invalidation Map

### Define Cache Dependencies

Configure cascading cache invalidation.

```ruby
config.cache_invalidation_map = {
  # When products cache is invalidated, also invalidate these:
  products: [:inventory, :reports, :homepage, :search_index],

  # When orders cache is invalidated:
  orders: [:user_orders, :reports, :dashboard, :analytics],

  # When users cache is invalidated:
  users: [:user_profile, :user_orders, :permissions]
}
```

--------------------------------

### How Cache Invalidation Works

Automatic cascade invalidation after successful writes.

```ruby
class Product::CreateService < Product::BaseService
  cache_contexts [:products]  # This service affects products cache
  auto_invalidate_cache true  # Invalidate after successful write

  # After successful create:
  # 1. Invalidates :products cache
  # 2. Also invalidates :inventory, :reports, :homepage, :search_index
end
```

--------------------------------

## Environment-Specific Configuration

### Per-Environment Settings

Configure differently per environment.

```ruby
BetterService.configure do |config|
  # Base settings
  config.instrumentation_enabled = true
  config.use_result_wrapper = true

  case Rails.env
  when "production"
    config.log_subscriber_enabled = false  # Use Datadog instead
    config.stats_subscriber_enabled = true
    config.instrumentation_include_args = false  # Security
    config.instrumentation_include_result = false

  when "staging"
    config.log_subscriber_enabled = true
    config.log_subscriber_level = :info
    config.stats_subscriber_enabled = true

  when "development"
    config.log_subscriber_enabled = true
    config.log_subscriber_level = :debug
    config.instrumentation_include_args = true
    config.instrumentation_include_result = true

  when "test"
    config.instrumentation_enabled = false
    config.log_subscriber_enabled = false
    config.stats_subscriber_enabled = false
  end
end
```

--------------------------------

## Accessing Configuration

### Read Configuration Values

Access configuration at runtime.

```ruby
# Get configuration value
BetterService.configuration.instrumentation_enabled
BetterService.configuration.log_subscriber_level
BetterService.configuration.cache_invalidation_map

# Check if service is excluded from instrumentation
BetterService.configuration.instrumentation_excluded_services.include?("MyService")
```

--------------------------------

## Service-Level Overrides

### Override Global Settings

Individual services can override global settings.

```ruby
class Product::CreateService < Product::BaseService
  # Override auto invalidation
  auto_invalidate_cache false

  # Override cache contexts
  cache_contexts [:products, :inventory]

  # Override transaction setting
  with_transaction true
end
```

--------------------------------
