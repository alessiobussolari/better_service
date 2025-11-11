# Configuration Guide

This guide covers all configuration options available in BetterService and how to use them effectively.

## Table of Contents

- [Installation](#installation)
- [Configuration Options](#configuration-options)
- [Instrumentation Settings](#instrumentation-settings)
- [Built-in Subscribers](#built-in-subscribers)
- [Custom Subscribers](#custom-subscribers)
- [Environment-Specific Configuration](#environment-specific-configuration)
- [Examples](#examples)

---

## Installation

Generate the configuration file:

```bash
rails generate better_service:install
```

This creates `config/initializers/better_service.rb` with all available options commented out.

---

## Configuration Options

All configuration is done in `config/initializers/better_service.rb`:

```ruby
BetterService.configure do |config|
  # Your configuration here
end
```

---

## Instrumentation Settings

BetterService uses `ActiveSupport::Notifications` to publish events about service execution. This enables monitoring, logging, and integration with observability tools.

### `instrumentation_enabled`

Enable or disable instrumentation globally.

**Type**: Boolean
**Default**: `true`

```ruby
config.instrumentation_enabled = true
```

When disabled, no events are published for any service, providing a performance optimization if you don't need observability.

**Disable instrumentation completely:**
```ruby
# In production, if you don't use monitoring
config.instrumentation_enabled = false
```

---

### `instrumentation_include_args`

Include service arguments (params) in event payloads.

**Type**: Boolean
**Default**: `true`

```ruby
config.instrumentation_include_args = true
```

**When to disable:**
- Arguments contain sensitive data (passwords, credit cards, tokens)
- Reduce payload size for high-throughput services
- Privacy compliance requirements (GDPR, HIPAA)

**Example:**
```ruby
# Disable if your services handle sensitive data
config.instrumentation_include_args = false
```

---

### `instrumentation_include_result`

Include service result in completion event payloads.

**Type**: Boolean
**Default**: `false`

```ruby
config.instrumentation_include_result = false
```

**When to enable:**
- Debugging in development/staging
- Detailed audit logging
- Result data is not sensitive

**When to keep disabled (recommended):**
- Production environments (performance)
- Large result payloads (collections, associations)
- Sensitive return values

**Example:**
```ruby
# Enable only in development
config.instrumentation_include_result = Rails.env.development?
```

---

### `instrumentation_excluded_services`

List of service class names to exclude from instrumentation.

**Type**: Array of Strings
**Default**: `[]`

```ruby
config.instrumentation_excluded_services = ["HealthCheckService", "MetricsService"]
```

**Use cases:**
- High-frequency services (health checks, metrics)
- Services that would generate noise in logs
- Internal utility services

**Example:**
```ruby
config.instrumentation_excluded_services = [
  "HealthCheckService",
  "MetricsService",
  "InternalCacheService"
]
```

---

## Built-in Subscribers

BetterService includes two built-in subscribers for common use cases.

### Log Subscriber

Logs all service events to `Rails.logger`.

#### `log_subscriber_enabled`

Enable the built-in log subscriber.

**Type**: Boolean
**Default**: `false`

```ruby
config.log_subscriber_enabled = true
```

**Output example:**
```
[BetterService] Product::CreateService started
[BetterService] Product::CreateService completed in 45.2ms
[BetterService] Product::IndexService cache hit (key: products_index:user_123:abc:products)
```

---

#### `log_subscriber_level`

Set the log level for service events.

**Type**: Symbol
**Default**: `:info`
**Valid values**: `:debug`, `:info`, `:warn`, `:error`

```ruby
config.log_subscriber_level = :debug
```

**Recommendations:**
- **Development**: `:debug` or `:info`
- **Staging**: `:info`
- **Production**: `:warn` or `:error` (or disable completely)

---

### Stats Subscriber

Collects execution statistics for all services.

#### `stats_subscriber_enabled`

Enable the built-in stats subscriber.

**Type**: Boolean
**Default**: `false`

```ruby
config.stats_subscriber_enabled = true
```

**Access statistics:**
```ruby
stats = BetterService::Subscribers::StatsSubscriber.stats

stats[:total_calls]
# => 142

stats[:services]["Product::CreateService"]
# => {
#   calls: 23,
#   total_duration: 1245.6,
#   avg_duration: 54.2,
#   min_duration: 12.3,
#   max_duration: 234.5,
#   failures: 2
# }
```

**Use cases:**
- Performance monitoring in development
- Identifying slow services
- Detecting failure patterns
- Capacity planning

---

## Custom Subscribers

Subscribe to BetterService events for custom integrations.

### Available Events

| Event | When | Payload |
|-------|------|---------|
| `service.started` | Service execution begins | `service`, `args`, `kwargs` |
| `service.completed` | Service succeeds | `service`, `duration`, `result` (optional) |
| `service.failed` | Service raises exception | `service`, `duration`, `error`, `error_class` |
| `cache.hit` | Cache hit for cacheable service | `service`, `key`, `context` |
| `cache.miss` | Cache miss for cacheable service | `service`, `key`, `context` |

See [Instrumentation Guide](../advanced/instrumentation.md) for detailed payload structure.

---

### DataDog Integration

```ruby
# config/initializers/better_service.rb

ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
  duration_ms = payload[:duration]
  service_name = payload[:service]

  # Send metrics to DataDog
  Datadog::Statsd.new.tap do |statsd|
    statsd.increment("better_service.calls", tags: ["service:#{service_name}"])
    statsd.histogram("better_service.duration", duration_ms, tags: ["service:#{service_name}"])
  end
end

ActiveSupport::Notifications.subscribe("service.failed") do |name, start, finish, id, payload|
  service_name = payload[:service]
  error_class = payload[:error_class]

  Datadog::Statsd.new.tap do |statsd|
    statsd.increment("better_service.failures", tags: [
      "service:#{service_name}",
      "error:#{error_class}"
    ])
  end
end
```

---

### New Relic Integration

```ruby
# config/initializers/better_service.rb

ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
  NewRelic::Agent.record_metric(
    "Custom/BetterService/#{payload[:service]}/duration",
    payload[:duration]
  )
end

ActiveSupport::Notifications.subscribe("service.failed") do |name, start, finish, id, payload|
  NewRelic::Agent.notice_error(
    payload[:error],
    custom_params: {
      service: payload[:service],
      duration: payload[:duration],
      error_class: payload[:error_class]
    }
  )
end
```

---

### Prometheus Integration

```ruby
# config/initializers/better_service.rb
require "prometheus/client"

prometheus = Prometheus::Client.registry

service_calls = prometheus.counter(
  :better_service_calls_total,
  docstring: "Total number of service calls",
  labels: [:service, :status]
)

service_duration = prometheus.histogram(
  :better_service_duration_seconds,
  docstring: "Service execution duration",
  labels: [:service]
)

ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
  service_calls.increment(labels: { service: payload[:service], status: "success" })
  service_duration.observe(payload[:duration] / 1000.0, labels: { service: payload[:service] })
end

ActiveSupport::Notifications.subscribe("service.failed") do |name, start, finish, id, payload|
  service_calls.increment(labels: { service: payload[:service], status: "failure" })
end
```

---

### Slack Notifications for Failures

```ruby
# config/initializers/better_service.rb

ActiveSupport::Notifications.subscribe("service.failed") do |name, start, finish, id, payload|
  next unless Rails.env.production?

  SlackNotifier.notify(
    channel: "#alerts",
    text: "Service Failed: #{payload[:service]}",
    fields: {
      "Error": payload[:error_class],
      "Duration": "#{payload[:duration]}ms",
      "Environment": Rails.env
    }
  )
end
```

---

## Environment-Specific Configuration

Use Rails environment helpers to configure differently per environment:

```ruby
BetterService.configure do |config|
  # Enable instrumentation everywhere
  config.instrumentation_enabled = true

  # Development: Verbose logging, include everything
  if Rails.env.development?
    config.log_subscriber_enabled = true
    config.log_subscriber_level = :debug
    config.stats_subscriber_enabled = true
    config.instrumentation_include_args = true
    config.instrumentation_include_result = true
  end

  # Test: Minimal logging, stats for test insights
  if Rails.env.test?
    config.log_subscriber_enabled = false
    config.stats_subscriber_enabled = true
    config.instrumentation_include_args = false
    config.instrumentation_include_result = false
  end

  # Staging: Moderate logging, exclude sensitive args
  if Rails.env.staging?
    config.log_subscriber_enabled = true
    config.log_subscriber_level = :info
    config.stats_subscriber_enabled = false
    config.instrumentation_include_args = false
    config.instrumentation_include_result = false
  end

  # Production: Minimal overhead, external monitoring only
  if Rails.env.production?
    config.log_subscriber_enabled = false
    config.stats_subscriber_enabled = false
    config.instrumentation_include_args = false
    config.instrumentation_include_result = false

    # Exclude high-frequency services
    config.instrumentation_excluded_services = [
      "HealthCheckService",
      "MetricsCollectionService"
    ]
  end
end
```

---

## Examples

### Minimal Configuration (Production)

Disable built-in subscribers, use external monitoring:

```ruby
BetterService.configure do |config|
  config.instrumentation_enabled = true
  config.instrumentation_include_args = false
  config.instrumentation_include_result = false
  config.log_subscriber_enabled = false
  config.stats_subscriber_enabled = false
end
```

---

### Development Configuration

Maximum observability for debugging:

```ruby
BetterService.configure do |config|
  config.instrumentation_enabled = true
  config.instrumentation_include_args = true
  config.instrumentation_include_result = true
  config.log_subscriber_enabled = true
  config.log_subscriber_level = :debug
  config.stats_subscriber_enabled = true
end
```

---

### Privacy-Compliant Configuration

Exclude sensitive data from events:

```ruby
BetterService.configure do |config|
  config.instrumentation_enabled = true

  # Never include args or results (may contain PII)
  config.instrumentation_include_args = false
  config.instrumentation_include_result = false

  # Exclude services that handle sensitive operations
  config.instrumentation_excluded_services = [
    "User::ChangePasswordService",
    "Payment::ProcessService",
    "User::LoginService"
  ]
end
```

---

## Performance Considerations

### Instrumentation Overhead

Instrumentation has minimal overhead:
- **Enabled**: ~0.1-0.3ms per service call
- **Disabled**: No overhead

### Recommendations

1. **Always enable in development/staging** - Invaluable for debugging
2. **Enable in production with caution** - Use external monitoring tools
3. **Exclude high-frequency services** - Health checks, internal services
4. **Disable result inclusion** - Reduces memory and payload size
5. **Use async event processing** - If you build custom subscribers

---

## Verification

Check your current configuration:

```ruby
# Rails console
config = BetterService.configuration

config.instrumentation_enabled
# => true

config.log_subscriber_enabled
# => false

config.instrumentation_excluded_services
# => ["HealthCheckService"]
```

---

## Resetting Configuration (Testing)

Reset to defaults (useful for tests):

```ruby
BetterService.reset_configuration!
```

---

## Next Steps

- **[Instrumentation Details](../advanced/instrumentation.md)** - Event payloads and examples
- **[Getting Started](getting-started.md)** - Back to getting started guide
- **[Error Handling](../advanced/error-handling.md)** - Exception handling patterns

---

**Related:**
- [Getting Started](getting-started.md)
- [Advanced Instrumentation](../advanced/instrumentation.md)
- [Testing Services](../testing.md)
