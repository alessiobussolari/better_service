# ActionService Examples

## Basic Custom Action
Create a service for custom business logic.

```ruby
class Order::ApproveService < BetterService::ActionService
  model_class Order
  action_name :approve

  schema do
    required(:id).filled(:integer)
  end

  search_with do
    { resource: model_class.find(params[:id]) }
  end

  process_with do |data|
    order = data[:resource]
    order.update!(status: 'approved', approved_at: Time.current)
    { resource: order }
  end
end

# Usage
result = Order::ApproveService.new(current_user, params: { id: 123 }).call
```

## With Transaction
Enable transactions for write operations.

```ruby
class Payment::ProcessService < BetterService::ActionService
  action_name :process
  self._transactional = true  # Enable transaction

  schema do
    required(:order_id).filled(:integer)
    required(:amount).filled(:decimal)
  end

  search_with do
    { order: Order.find(params[:order_id]) }
  end

  process_with do |data|
    order = data[:order]

    payment = Payment.create!(
      order: order,
      amount: params[:amount],
      status: 'processing'
    )

    # Charge payment gateway
    gateway_response = PaymentGateway.charge(params[:amount])

    payment.update!(
      status: 'completed',
      transaction_id: gateway_response.id
    )

    { resource: payment }
  end
end
```

## State Transition
Handle complex state changes.

```ruby
class Article::PublishService < BetterService::ActionService
  model_class Article
  action_name :publish
  cache_contexts :articles

  schema do
    required(:id).filled(:integer)
    optional(:publish_at).maybe(:time)
  end

  authorize_with do
    article = model_class.find(params[:id])
    article.author_id == user.id || user.editor?
  end

  search_with do
    article = model_class.find(params[:id])

    unless article.draft?
      raise BetterService::Errors::Runtime::ValidationError.new(
        "Article must be in draft status"
      )
    end

    { resource: article }
  end

  process_with do |data|
    article = data[:resource]

    article.update!(
      status: 'published',
      published_at: params[:publish_at] || Time.current
    )

    # Update search index
    article.reindex_for_search

    # Notify subscribers
    NotificationService.notify_subscribers(article) if article.published_at <= Time.current

    invalidate_cache_for(user)

    { resource: article }
  end
end
```

## External API Integration
Integrate with external services.

```ruby
class Order::SendToWarehouseService < BetterService::ActionService
  action_name :send_to_warehouse
  self._transactional = false  # External API, no DB transaction needed

  schema do
    required(:order_id).filled(:integer)
  end

  search_with do
    order = Order.includes(:items, :shipping_address).find(params[:order_id])

    unless order.confirmed?
      raise BetterService::Errors::Runtime::ValidationError.new(
        "Order must be confirmed first"
      )
    end

    { resource: order }
  end

  process_with do |data|
    order = data[:resource]

    # Send to external warehouse API
    response = WarehouseAPI.create_fulfillment(
      order_id: order.id,
      items: order.items.map(&:to_warehouse_format),
      shipping_address: order.shipping_address.to_h
    )

    # Update order with warehouse reference
    order.update!(warehouse_ref: response.fulfillment_id)

    { resource: order, warehouse_response: response }
  end
end
```

## Batch Operation
Process multiple records.

```ruby
class Product::BulkArchiveService < BetterService::ActionService
  action_name :bulk_archive
  cache_contexts :products

  schema do
    required(:product_ids).array(:integer, min_size?: 1)
  end

  authorize_with do
    user.admin?
  end

  search_with do
    products = Product.where(id: params[:product_ids])

    if products.count != params[:product_ids].count
      raise BetterService::Errors::Runtime::ValidationError.new(
        "Some products not found"
      )
    end

    { resources: products }
  end

  process_with do |data|
    products = data[:resources]

    archived_count = 0
    products.each do |product|
      product.update!(archived_at: Time.current, archived_by: user)
      archived_count += 1
    end

    invalidate_cache_for(user)

    {
      resource: products,
      metadata: { archived_count: archived_count }
    }
  end
end
```

## Email/Notification Action
Send communications.

```ruby
class User::SendWelcomeEmailService < BetterService::ActionService
  action_name :send_welcome
  self._transactional = false

  schema do
    required(:user_id).filled(:integer)
  end

  search_with do
    { resource: User.find(params[:user_id]) }
  end

  process_with do |data|
    user_record = data[:resource]

    # Send welcome email
    UserMailer.welcome(user_record).deliver_later

    # Track event
    Analytics.track('welcome_email_sent', user_id: user_record.id)

    { resource: user_record }
  end
end
```

## Report Generation
Generate reports or exports.

```ruby
class Report::GenerateMonthlyService < BetterService::ActionService
  action_name :generate_monthly
  self._transactional = false
  self._allow_nil_user = true

  schema do
    required(:year).filled(:integer)
    required(:month).filled(:integer, gteq?: 1, lteq?: 12)
  end

  search_with do
    start_date = Date.new(params[:year], params[:month], 1)
    end_date = start_date.end_of_month

    {
      start_date: start_date,
      end_date: end_date
    }
  end

  process_with do |data|
    orders = Order.where(
      created_at: data[:start_date]..data[:end_date]
    )

    report_data = {
      total_orders: orders.count,
      total_revenue: orders.sum(:total),
      average_order: orders.average(:total),
      top_products: calculate_top_products(orders)
    }

    { resource: report_data }
  end

  private

  def calculate_top_products(orders)
    OrderItem.where(order: orders)
      .group(:product_id)
      .sum(:quantity)
      .sort_by { |_, qty| -qty }
      .first(10)
  end
end
```

## Retry Logic for Failed Operations
Automatically retry failed external API calls.

```ruby
class Payment::ChargeService < BetterService::ActionService
  model_class Order
  action_name :charge

  MAX_RETRIES = 3
  RETRY_DELAY = 2.seconds

  schema do
    required(:order_id).filled(:integer)
  end

  search_with do
    { resource: model_class.find(params[:order_id]) }
  end

  process_with do |data|
    order = data[:resource]
    attempts = 0

    begin
      attempts += 1

      charge = Stripe::Charge.create(
        amount: (order.total * 100).to_i,
        currency: 'usd',
        source: order.payment_token
      )

      order.update!(
        payment_status: 'paid',
        charge_id: charge.id
      )

      { resource: order, charge: charge }
    rescue Stripe::RateLimitError, Stripe::APIConnectionError => e
      if attempts < MAX_RETRIES
        sleep(RETRY_DELAY * attempts)
        retry
      else
        Rails.logger.error("Payment failed after #{attempts} attempts: #{e.message}")
        raise BetterService::Errors::Runtime::ExecutionError.new(
          "Payment failed after #{MAX_RETRIES} attempts"
        )
      end
    end
  end
end
```

## Rate Limiting for Sensitive Actions
Prevent abuse with rate limiting.

```ruby
class User::SendPasswordResetService < BetterService::ActionService
  action_name :send_password_reset
  self._transactional = false

  schema do
    required(:email).filled(:string)
  end

  search_with do
    user_record = User.find_by(email: params[:email].downcase)

    unless user_record
      # Don't reveal if email exists
      raise BetterService::Errors::Runtime::ValidationError.new(
        "If the email exists, reset instructions will be sent"
      )
    end

    # Check rate limit (5 requests per hour)
    cache_key = "password_reset_limit:#{user_record.id}"
    attempts = Rails.cache.read(cache_key) || 0

    if attempts >= 5
      raise BetterService::Errors::Runtime::ValidationError.new(
        "Too many reset requests. Please try again later."
      )
    end

    { resource: user_record, cache_key: cache_key, attempts: attempts }
  end

  process_with do |data|
    user_record = data[:resource]

    # Generate token
    token = user_record.generate_reset_token!

    # Send email
    UserMailer.password_reset(user_record, token).deliver_later

    # Increment rate limit counter
    Rails.cache.write(
      data[:cache_key],
      data[:attempts] + 1,
      expires_in: 1.hour
    )

    { resource: user_record }
  end
end
```

## Action with Approval Workflow
Pending approval before execution.

```ruby
class Expense::ApproveService < BetterService::ActionService
  model_class Expense
  action_name :approve

  schema do
    required(:id).filled(:integer)
    optional(:notes).maybe(:string)
  end

  authorize_with do
    user.manager? || user.admin?
  end

  search_with do
    expense = model_class.find(params[:id])

    unless expense.pending?
      raise BetterService::Errors::Runtime::ValidationError.new(
        "Only pending expenses can be approved"
      )
    end

    { resource: expense }
  end

  process_with do |data|
    expense = data[:resource]

    expense.update!(
      status: 'approved',
      approved_by_id: user.id,
      approved_at: Time.current,
      approval_notes: params[:notes]
    )

    # Trigger payment workflow
    ExpensePaymentWorkflow.new(user, params: { expense_id: expense.id }).call

    # Notify employee
    ExpenseMailer.approved(expense).deliver_later

    { resource: expense }
  end
end
```

## Idempotent Action
Safe to execute multiple times.

```ruby
class Order::FulfillService < BetterService::ActionService
  model_class Order
  action_name :fulfill

  schema do
    required(:order_id).filled(:integer)
    required(:tracking_number).filled(:string)
  end

  search_with do
    { resource: model_class.find(params[:order_id]) }
  end

  process_with do |data|
    order = data[:resource]

    # Idempotent: Check if already fulfilled
    if order.fulfilled?
      # Already fulfilled with same tracking number?
      if order.tracking_number == params[:tracking_number]
        return { resource: order, already_fulfilled: true }
      else
        raise BetterService::Errors::Runtime::ValidationError.new(
          "Order already fulfilled with different tracking number"
        )
      end
    end

    # Fulfill order
    order.update!(
      status: 'fulfilled',
      tracking_number: params[:tracking_number],
      fulfilled_at: Time.current,
      fulfilled_by_id: user.id
    )

    # Send notification (only once)
    OrderMailer.shipped(order).deliver_later

    { resource: order, already_fulfilled: false }
  end
end
```

## Background Job Integration
Enqueue long-running tasks.

```ruby
class Report::GenerateLargeExportService < BetterService::ActionService
  action_name :generate_export
  self._transactional = false

  schema do
    required(:start_date).filled(:date)
    required(:end_date).filled(:date)
    required(:format).filled(:string, included_in?: %w[csv xlsx pdf])
  end

  search_with do
    # Validate date range
    if params[:end_date] < params[:start_date]
      raise BetterService::Errors::Runtime::ValidationError.new(
        "End date must be after start date"
      )
    end

    {}
  end

  process_with do |data|
    # Create export record
    export = Export.create!(
      user: user,
      start_date: params[:start_date],
      end_date: params[:end_date],
      format: params[:format],
      status: 'queued'
    )

    # Enqueue background job
    GenerateExportJob.perform_later(export.id)

    # Notify user when ready
    ExportMailer.queued(export).deliver_later

    {
      resource: export,
      message: "Export queued. You'll receive an email when it's ready."
    }
  end
end
```
