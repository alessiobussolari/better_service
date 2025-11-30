# Configuration

Configure BetterService for your application.

---

## Setup

### Generate Configuration

Create the configuration file.

```bash
rails g better_service:install
```

Creates:
- `config/initializers/better_service.rb`
- `config/locales/better_service.en.yml`

--------------------------------

## Configuration Options

### Full Configuration

All available configuration options.

```ruby
# config/initializers/better_service.rb
BetterService.configure do |config|
  # Instrumentation
  config.instrumentation_enabled = true
  config.instrumentation_include_args = false
  config.instrumentation_include_result = false
  config.instrumentation_excluded_services = []

  # Logging
  config.log_subscriber_enabled = true
  config.log_subscriber_level = :info

  # Stats
  config.stats_subscriber_enabled = false

  # Response format
  config.use_result_wrapper = true

  # Cache
  config.cache_invalidation_map = {}
end
```

--------------------------------

## Instrumentation

### Enable/Disable Instrumentation

Control event publishing.

```ruby
# Enable all instrumentation events
config.instrumentation_enabled = true

# Disable instrumentation (useful for tests)
config.instrumentation_enabled = false
```

--------------------------------

### Include Arguments

Include service arguments in event payloads.

```ruby
# Include params in events (may expose sensitive data!)
config.instrumentation_include_args = true

# Exclude params (safer for production)
config.instrumentation_include_args = false
```

--------------------------------

### Include Results

Include service results in event payloads.

```ruby
# Include result in events
config.instrumentation_include_result = true

# Exclude result
config.instrumentation_include_result = false
```

--------------------------------

### Exclude Services

Exclude specific services from instrumentation.

```ruby
config.instrumentation_excluded_services = [
  "HealthCheck::PingService",
  "Auth::TokenRefreshService",
  "Metrics::CollectService"
]
```

--------------------------------

## Logging

### Log Subscriber

Enable built-in logging.

```ruby
# Enable log subscriber
config.log_subscriber_enabled = true

# Set log level
config.log_subscriber_level = :info  # :debug, :info, :warn, :error

# Log output:
# [BetterService] Product::CreateService completed in 45.23ms (action: created)
# [BetterService] Product::ShowService failed in 12.10ms (error: ResourceNotFoundError)
```

--------------------------------

## Stats Collection

### Stats Subscriber

Enable metrics collection.

```ruby
# Enable stats subscriber
config.stats_subscriber_enabled = true

# Access stats:
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

## Cache Configuration

### Cache Invalidation Map

Define cache dependencies.

```ruby
config.cache_invalidation_map = {
  # When products cache invalidates, also invalidate:
  products: [:inventory, :reports, :homepage],

  # When orders cache invalidates:
  orders: [:user_orders, :reports, :dashboard],

  # When users cache invalidates:
  users: [:user_profile, :user_orders]
}
```

--------------------------------

### How Cache Invalidation Works

Automatic cascade invalidation.

```ruby
class Product::CreateService < Product::BaseService
  cache_contexts [:products]
  auto_invalidate_cache true

  # After successful create:
  # 1. Invalidates :products cache
  # 2. Also invalidates :inventory, :reports, :homepage
end
```

--------------------------------

## Environment Configuration

### Per-Environment Settings

Configure differently per environment.

```ruby
BetterService.configure do |config|
  config.instrumentation_enabled = true
  config.use_result_wrapper = true

  case Rails.env
  when "production"
    config.log_subscriber_enabled = false
    config.stats_subscriber_enabled = true
    config.instrumentation_include_args = false
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

## Custom Subscribers

### Creating Custom Subscribers

Subscribe to BetterService events.

```ruby
# config/initializers/better_service_monitoring.rb

# Subscribe to completions
ActiveSupport::Notifications.subscribe("service.completed.better_service") do |name, start, finish, id, payload|
  duration_ms = (finish - start) * 1000

  Rails.logger.info({
    event: name,
    service: payload[:service],
    user_id: payload[:user_id],
    duration_ms: duration_ms.round(2)
  }.to_json)
end

# Subscribe to failures
ActiveSupport::Notifications.subscribe("service.failed.better_service") do |name, start, finish, id, payload|
  Sentry.capture_message("Service failed", extra: {
    service: payload[:service],
    error: payload[:error].message,
    user_id: payload[:user_id]
  })
end
```

--------------------------------

### Datadog Integration

Send metrics to Datadog.

```ruby
class DatadogSubscriber
  def self.subscribe
    ActiveSupport::Notifications.subscribe(/\.better_service$/) do |name, start, finish, id, payload|
      event_type = name.split(".").first
      duration = (finish - start) * 1000

      tags = ["service:#{payload[:service]}", "event:#{event_type}"]

      case event_type
      when "service.completed"
        Datadog::Statsd.increment("better_service.success", tags: tags)
        Datadog::Statsd.histogram("better_service.duration", duration, tags: tags)
      when "service.failed"
        Datadog::Statsd.increment("better_service.failure", tags: tags)
      end
    end
  end
end

DatadogSubscriber.subscribe if Rails.env.production?
```

--------------------------------

## Service-Level Overrides

### Override in Services

Individual services can override global settings.

```ruby
class Product::CreateService < Product::BaseService
  # Override transaction setting
  with_transaction true

  # Override cache settings
  cache_contexts [:products, :inventory]
  auto_invalidate_cache true
end

class Product::IndexService < Product::BaseService
  # No transaction for read operations
  # No auto_invalidate_cache for reads
end
```

--------------------------------

## Available Events

### Instrumentation Events

Events published by BetterService.

```ruby
# Event                              | When
# -----------------------------------|----------------------------
# service.started.better_service     | Service call begins
# service.completed.better_service   | Service succeeds
# service.failed.better_service      | Service fails
# cache.hit.better_service           | Cached result returned
# cache.miss.better_service          | Fresh execution needed
```

--------------------------------

## Accessing Configuration

### Read Configuration Values

Access configuration at runtime.

```ruby
# Get configuration values
BetterService.configuration.instrumentation_enabled
BetterService.configuration.log_subscriber_level
BetterService.configuration.cache_invalidation_map

# Check if service is excluded
excluded = BetterService.configuration.instrumentation_excluded_services
excluded.include?("MyService")
```

--------------------------------

## Best Practices

### Configuration Guidelines

Follow these guidelines.

```ruby
# 1. Disable instrumentation in tests
config.instrumentation_enabled = false if Rails.env.test?

# 2. Don't log sensitive data in production
config.instrumentation_include_args = false
config.instrumentation_include_result = false

# 3. Use appropriate log levels
# Development: :debug
# Staging: :info
# Production: :warn or disable

# 4. Exclude high-frequency services
config.instrumentation_excluded_services = [
  "HealthCheck::PingService"  # Called every few seconds
]

# 5. Define cache dependencies clearly
config.cache_invalidation_map = {
  products: [:search_index, :reports]  # Document why
}
```

--------------------------------
