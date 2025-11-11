# Custom Subscribers

Examples of creating custom subscribers for specific monitoring needs.

## Basic Custom Subscriber

Create a simple subscriber for tracking service metrics.

```ruby
# app/subscribers/metrics_subscriber.rb
class MetricsSubscriber
  def self.attach
    ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
      service_name = payload[:service_name]
      duration = payload[:duration]
      success = payload[:success]

      # Increment execution counter
      Metrics.increment("service.executions", tags: ["service:#{service_name}"])

      # Track duration
      Metrics.histogram("service.duration", duration, tags: ["service:#{service_name}"])

      # Track success/failure
      if success
        Metrics.increment("service.success", tags: ["service:#{service_name}"])
      end
    end

    ActiveSupport::Notifications.subscribe("service.failed") do |name, start, finish, id, payload|
      service_name = payload[:service_name]
      error_class = payload[:error_class]

      Metrics.increment("service.failure", tags: [
        "service:#{service_name}",
        "error:#{error_class}"
      ])
    end
  end
end

# In initializer
MetricsSubscriber.attach
```

## Subscriber with State

Track data across multiple events with instance variables.

```ruby
# app/subscribers/performance_tracker.rb
class PerformanceTracker
  def self.attach
    @slow_services = []
    @error_counts = Hash.new(0)

    ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
      service_name = payload[:service_name]
      duration = payload[:duration]

      # Track slow services
      if duration > 1000
        @slow_services << {
          service: service_name,
          duration: duration,
          user_id: payload[:user_id],
          timestamp: payload[:timestamp]
        }
      end
    end

    ActiveSupport::Notifications.subscribe("service.failed") do |name, start, finish, id, payload|
      error_class = payload[:error_class]
      @error_counts[error_class] += 1
    end
  end

  def self.slow_services
    @slow_services ||= []
  end

  def self.error_counts
    @error_counts ||= Hash.new(0)
  end

  def self.reset!
    @slow_services = []
    @error_counts = Hash.new(0)
  end
end

# In initializer
PerformanceTracker.attach

# Later, access tracked data
PerformanceTracker.slow_services
# => [{ service: "Product::CreateService", duration: 1250, ... }]

PerformanceTracker.error_counts
# => { "ActiveRecord::RecordInvalid" => 5, "ActiveRecord::RecordNotFound" => 2 }
```

## Alert Subscriber

Send alerts when specific conditions are met.

```ruby
# app/subscribers/alert_subscriber.rb
class AlertSubscriber
  SLOW_THRESHOLD = 2000      # 2 seconds
  ERROR_THRESHOLD = 5         # 5 errors in window
  CRITICAL_SERVICES = ["Payment::ProcessService", "Order::CreateService"]

  def self.attach
    @error_window = []

    ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
      duration = payload[:duration]
      service_name = payload[:service_name]

      # Alert on slow services
      if duration > SLOW_THRESHOLD
        send_alert(
          level: :warning,
          title: "Slow Service Detected",
          message: "#{service_name} took #{duration}ms (threshold: #{SLOW_THRESHOLD}ms)",
          details: {
            service: service_name,
            duration: duration,
            user_id: payload[:user_id]
          }
        )
      end

      # Alert on critical service completion
      if CRITICAL_SERVICES.include?(service_name)
        send_alert(
          level: :info,
          title: "Critical Service Executed",
          message: "#{service_name} completed successfully in #{duration}ms",
          details: {
            service: service_name,
            duration: duration,
            user_id: payload[:user_id]
          }
        )
      end
    end

    ActiveSupport::Notifications.subscribe("service.failed") do |name, start, finish, id, payload|
      service_name = payload[:service_name]
      error_class = payload[:error_class]
      error_message = payload[:error_message]

      # Track errors in sliding window
      @error_window << Time.current
      @error_window.reject! { |time| time < 5.minutes.ago }

      # Alert if too many errors
      if @error_window.size >= ERROR_THRESHOLD
        send_alert(
          level: :critical,
          title: "High Error Rate",
          message: "#{@error_window.size} service failures in last 5 minutes",
          details: {
            latest_service: service_name,
            latest_error: error_class,
            error_count: @error_window.size
          }
        )
      end

      # Always alert on critical service failures
      if CRITICAL_SERVICES.include?(service_name)
        send_alert(
          level: :critical,
          title: "Critical Service Failed",
          message: "#{service_name} failed: #{error_message}",
          details: {
            service: service_name,
            error_class: error_class,
            error_message: error_message,
            user_id: payload[:user_id],
            backtrace: payload[:error_backtrace]
          }
        )
      end
    end
  end

  private

  def self.send_alert(level:, title:, message:, details: {})
    # Send to Slack
    SlackNotifier.send(
      level: level,
      title: title,
      message: message,
      details: details
    )

    # Log alert
    case level
    when :critical
      Rails.logger.error "[ALERT:CRITICAL] #{title}: #{message}"
    when :warning
      Rails.logger.warn "[ALERT:WARNING] #{title}: #{message}"
    when :info
      Rails.logger.info "[ALERT:INFO] #{title}: #{message}"
    end
  end
end

# In initializer
AlertSubscriber.attach
```

## Cache Effectiveness Subscriber

Track and analyze cache performance.

```ruby
# app/subscribers/cache_analyzer.rb
class CacheAnalyzer
  def self.attach
    @cache_stats = Hash.new { |h, k| h[k] = { hits: 0, misses: 0 } }

    ActiveSupport::Notifications.subscribe("cache.hit") do |name, start, finish, id, payload|
      service_name = payload[:service_name]
      @cache_stats[service_name][:hits] += 1
    end

    ActiveSupport::Notifications.subscribe("cache.miss") do |name, start, finish, id, payload|
      service_name = payload[:service_name]
      @cache_stats[service_name][:misses] += 1
    end
  end

  def self.cache_stats
    @cache_stats ||= Hash.new { |h, k| h[k] = { hits: 0, misses: 0 } }
  end

  def self.hit_rate_for(service_name)
    stats = @cache_stats[service_name]
    total = stats[:hits] + stats[:misses]
    return 0 if total.zero?

    (stats[:hits].to_f / total * 100).round(2)
  end

  def self.report
    report = {}

    @cache_stats.each do |service_name, stats|
      total = stats[:hits] + stats[:misses]
      next if total.zero?

      report[service_name] = {
        hits: stats[:hits],
        misses: stats[:misses],
        total: total,
        hit_rate: (stats[:hits].to_f / total * 100).round(2)
      }
    end

    report.sort_by { |_, data| -data[:hit_rate] }.to_h
  end

  def self.reset!
    @cache_stats = Hash.new { |h, k| h[k] = { hits: 0, misses: 0 } }
  end
end

# In initializer
CacheAnalyzer.attach

# Later, analyze cache performance
CacheAnalyzer.cache_stats
# => {
#   "Product::IndexService" => { hits: 45, misses: 5 },
#   "Category::IndexService" => { hits: 20, misses: 30 }
# }

CacheAnalyzer.hit_rate_for("Product::IndexService")
# => 90.0

CacheAnalyzer.report
# => {
#   "Product::IndexService" => { hits: 45, misses: 5, total: 50, hit_rate: 90.0 },
#   "Category::IndexService" => { hits: 20, misses: 30, total: 50, hit_rate: 40.0 }
# }
```

## Background Job Subscriber

Offload heavy processing to background jobs.

```ruby
# app/subscribers/background_metrics_subscriber.rb
class BackgroundMetricsSubscriber
  def self.attach
    ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
      # Send metrics asynchronously to avoid blocking
      MetricsJob.perform_later(
        event_type: 'completed',
        service_name: payload[:service_name],
        duration: payload[:duration],
        user_id: payload[:user_id],
        timestamp: payload[:timestamp]
      )
    end

    ActiveSupport::Notifications.subscribe("service.failed") do |name, start, finish, id, payload|
      # Send error reports asynchronously
      ErrorReportJob.perform_later(
        service_name: payload[:service_name],
        error_class: payload[:error_class],
        error_message: payload[:error_message],
        user_id: payload[:user_id],
        backtrace: payload[:error_backtrace]
      )
    end
  end
end

# app/jobs/metrics_job.rb
class MetricsJob < ApplicationJob
  queue_as :metrics

  def perform(event_type:, service_name:, duration:, user_id:, timestamp:)
    # Heavy external API call - won't block service execution
    ExternalMetricsAPI.send(
      event: event_type,
      service: service_name,
      duration: duration,
      user_id: user_id,
      timestamp: timestamp
    )
  rescue => error
    Rails.logger.error "Failed to send metrics: #{error.message}"
  end
end

# In initializer
BackgroundMetricsSubscriber.attach
```

## Selective Subscriber

Subscribe only to specific services or patterns.

```ruby
# app/subscribers/critical_services_subscriber.rb
class CriticalServicesSubscriber
  CRITICAL_PATTERNS = [
    /^Payment::/,
    /^Order::/,
    /^Billing::/
  ]

  def self.attach
    ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
      service_name = payload[:service_name]

      # Only track critical services
      if critical_service?(service_name)
        CriticalServicesMonitor.record_completion(
          service: service_name,
          duration: payload[:duration],
          user_id: payload[:user_id]
        )
      end
    end

    ActiveSupport::Notifications.subscribe("service.failed") do |name, start, finish, id, payload|
      service_name = payload[:service_name]

      # Alert immediately on critical service failures
      if critical_service?(service_name)
        PagerDuty.trigger_incident(
          title: "Critical Service Failure",
          description: "#{service_name} failed: #{payload[:error_message]}",
          severity: 'critical',
          details: payload
        )
      end
    end
  end

  private

  def self.critical_service?(service_name)
    CRITICAL_PATTERNS.any? { |pattern| service_name.match?(pattern) }
  end
end

# In initializer
CriticalServicesSubscriber.attach
```

## Unsubscribing from Events

Manage subscription lifecycle with unsubscribe.

```ruby
# app/subscribers/temporary_debug_subscriber.rb
class TemporaryDebugSubscriber
  def self.attach
    @subscription = ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
      Rails.logger.debug "[DEBUG] Service completed: #{payload.inspect}"
    end
  end

  def self.detach
    ActiveSupport::Notifications.unsubscribe(@subscription) if @subscription
    @subscription = nil
  end

  def self.attached?
    @subscription.present?
  end
end

# In Rails console for temporary debugging
TemporaryDebugSubscriber.attach

# Run some services...

# Stop debugging
TemporaryDebugSubscriber.detach
```

## Multi-Event Subscriber

Subscribe to multiple event types in one subscriber.

```ruby
# app/subscribers/comprehensive_subscriber.rb
class ComprehensiveSubscriber
  def self.attach
    # Subscribe to all service and cache events
    ActiveSupport::Notifications.subscribe(/^(service|cache)\./) do |name, start, finish, id, payload|
      event_type = name.split('.').last
      service_name = payload[:service_name]

      case event_type
      when 'started'
        handle_started(service_name, payload)
      when 'completed'
        handle_completed(service_name, payload)
      when 'failed'
        handle_failed(service_name, payload)
      when 'hit', 'miss'
        handle_cache_event(name, service_name, payload)
      end
    end
  end

  private

  def self.handle_started(service_name, payload)
    Rails.logger.info "[START] #{service_name} (user: #{payload[:user_id]})"
  end

  def self.handle_completed(service_name, payload)
    duration = payload[:duration]
    Rails.logger.info "[COMPLETE] #{service_name} in #{duration}ms"

    # Track in metrics
    Metrics.histogram("service.duration", duration, tags: ["service:#{service_name}"])
  end

  def self.handle_failed(service_name, payload)
    error_class = payload[:error_class]
    Rails.logger.error "[FAILED] #{service_name}: #{error_class}"

    # Track error
    Metrics.increment("service.errors", tags: [
      "service:#{service_name}",
      "error:#{error_class}"
    ])
  end

  def self.handle_cache_event(event_name, service_name, payload)
    event_type = event_name.split('.').last
    Rails.logger.debug "[CACHE #{event_type.upcase}] #{service_name}"
  end
end

# In initializer
ComprehensiveSubscriber.attach
```

## Error-Safe Subscriber

Ensure subscriber errors don't break service execution.

```ruby
# app/subscribers/safe_metrics_subscriber.rb
class SafeMetricsSubscriber
  def self.attach
    ActiveSupport::Notifications.subscribe("service.completed") do |name, start, finish, id, payload|
      begin
        # Potentially failing metrics code
        ExternalMetricsAPI.send(payload)
      rescue => error
        # Log error but don't raise - don't break service execution
        Rails.logger.error "Metrics subscriber error: #{error.message}"
        Rails.logger.error error.backtrace.join("\n")

        # Optionally track subscriber errors
        Metrics.increment("subscriber.errors", tags: ["subscriber:SafeMetricsSubscriber"])
      end
    end
  end
end

# In initializer
SafeMetricsSubscriber.attach

# Service execution continues even if subscriber fails
```
