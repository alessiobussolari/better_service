# Custom Action Service Examples

## Basic Custom Action
Create a service for custom business logic using the base service.

```ruby
class Order::ApproveService < Order::BaseService
  # Action name for metadata
  performed_action :approve

  schema do
    required(:id).filled(:integer)
  end

  search_with do
    { resource: order_repository.find(params[:id]) }
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
class Payment::ProcessService < Payment::BaseService
  performed_action :process
  with_transaction true  # Enable transaction

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
      status: 'completed'
    )

    order.update!(payment_status: 'paid')

    { resource: payment }
  end
end
```

## With Authorization
Protect custom actions with authorization.

```ruby
class Article::PublishService < Article::BaseService
  performed_action :publish
  with_transaction true

  schema do
    required(:id).filled(:integer)
  end

  authorize_with do
    user.can_publish_articles?
  end

  search_with do
    { resource: article_repository.find(params[:id]) }
  end

  process_with do |data|
    article = data[:resource]
    article.update!(
      published: true,
      published_at: Time.current,
      published_by: user
    )
    { resource: article }
  end

  respond_with do |data|
    success_result(message("publish.success"), data)
  end
end
```

## Complex Multi-Step Action
Handle complex operations with multiple steps.

```ruby
class Order::SendToWarehouseService < Order::BaseService
  performed_action :send_to_warehouse
  with_transaction true

  schema do
    required(:id).filled(:integer)
    optional(:priority).filled(:string, included_in?: %w[normal high urgent])
  end

  authorize_with do
    user.warehouse_access?
  end

  search_with do
    order = order_repository.find(params[:id])
    raise BetterService::Errors::Runtime::ValidationError.new(
      message: "Order not ready for warehouse",
      code: :order_not_ready
    ) unless order.ready_for_warehouse?

    { resource: order }
  end

  process_with do |data|
    order = data[:resource]

    # Create warehouse request
    warehouse_request = WarehouseRequest.create!(
      order: order,
      priority: params[:priority] || 'normal',
      requested_by: user,
      requested_at: Time.current
    )

    # Update order status
    order.update!(
      status: 'sent_to_warehouse',
      warehouse_request: warehouse_request
    )

    # Notify warehouse
    WarehouseNotificationJob.perform_later(warehouse_request.id)

    { resource: order, warehouse_request: warehouse_request }
  end
end
```

## Bulk Operations
Handle bulk actions on multiple records.

```ruby
class Product::BulkArchiveService < Product::BaseService
  performed_action :bulk_archive
  with_transaction true

  schema do
    required(:ids).array(:integer, min_size?: 1)
    optional(:reason).filled(:string)
  end

  authorize_with do
    user.admin?
  end

  search_with do
    products = product_repository.search(id: params[:ids])

    raise BetterService::Errors::Runtime::ResourceNotFoundError.new(
      message: "Some products not found",
      code: :products_not_found
    ) if products.count != params[:ids].length

    { items: products }
  end

  process_with do |data|
    archived_count = 0

    data[:items].each do |product|
      product.update!(
        archived: true,
        archived_at: Time.current,
        archived_by: user,
        archive_reason: params[:reason]
      )
      archived_count += 1
    end

    {
      items: data[:items],
      metadata: { archived_count: archived_count }
    }
  end
end
```

## Email/Notification Action
Send emails or notifications as a service action.

```ruby
class User::SendWelcomeEmailService < User::BaseService
  performed_action :send_welcome_email
  # No transaction needed for non-database operations

  schema do
    required(:id).filled(:integer)
  end

  search_with do
    { resource: user_repository.find(params[:id]) }
  end

  process_with do |data|
    target_user = data[:resource]

    UserMailer.welcome_email(target_user).deliver_later

    target_user.update!(welcome_email_sent_at: Time.current)

    { resource: target_user }
  end
end
```

## Report Generation
Generate reports as an action.

```ruby
class Report::GenerateMonthlyService < Report::BaseService
  performed_action :generate_monthly
  with_transaction true

  schema do
    required(:month).filled(:integer, gteq?: 1, lteq?: 12)
    required(:year).filled(:integer)
    optional(:format).filled(:string, included_in?: %w[pdf csv excel])
  end

  search_with do
    start_date = Date.new(params[:year], params[:month], 1)
    end_date = start_date.end_of_month

    {
      transactions: Transaction.where(date: start_date..end_date),
      period: { start_date: start_date, end_date: end_date }
    }
  end

  process_with do |data|
    report = Report.create!(
      type: 'monthly',
      period_start: data[:period][:start_date],
      period_end: data[:period][:end_date],
      format: params[:format] || 'pdf',
      generated_by: user,
      status: 'generating'
    )

    # Queue report generation
    ReportGenerationJob.perform_later(report.id, data[:transactions].pluck(:id))

    { resource: report }
  end
end
```

## External API Integration
Integrate with external services.

```ruby
class Payment::ChargeService < Payment::BaseService
  performed_action :charge
  with_transaction true

  schema do
    required(:order_id).filled(:integer)
    required(:payment_method_id).filled(:string)
  end

  search_with do
    order = Order.find(params[:order_id])
    payment_method = user.payment_methods.find_by!(stripe_id: params[:payment_method_id])

    { order: order, payment_method: payment_method }
  end

  process_with do |data|
    order = data[:order]
    payment_method = data[:payment_method]

    # Call Stripe API
    stripe_charge = Stripe::PaymentIntent.create(
      amount: (order.total * 100).to_i,
      currency: 'usd',
      payment_method: payment_method.stripe_id,
      confirm: true
    )

    # Record payment
    payment = Payment.create!(
      order: order,
      stripe_payment_intent_id: stripe_charge.id,
      amount: order.total,
      status: stripe_charge.status
    )

    order.update!(payment_status: 'paid', payment: payment)

    { resource: payment, order: order }
  rescue Stripe::CardError => e
    raise BetterService::Errors::Runtime::ExecutionError.new(
      message: "Payment failed: #{e.message}",
      code: :payment_failed,
      original_error: e
    )
  end
end
```

## Password Reset Action
Handle password reset flow.

```ruby
class User::SendPasswordResetService < User::BaseService
  performed_action :send_password_reset
  allow_nil_user true  # Public action

  schema do
    required(:email).filled(:string, format?: URI::MailTo::EMAIL_REGEXP)
  end

  search_with do
    user_account = User.find_by(email: params[:email])
    { resource: user_account }  # Can be nil
  end

  process_with do |data|
    user_account = data[:resource]

    if user_account
      # Generate reset token
      token = SecureRandom.urlsafe_base64(32)
      user_account.update!(
        reset_password_token: token,
        reset_password_sent_at: Time.current
      )

      # Send email
      UserMailer.password_reset(user_account, token).deliver_later
    end

    # Always return success to prevent email enumeration
    { resource: nil }
  end

  respond_with do |_data|
    success_result("If an account exists, a password reset email has been sent", {})
  end
end
```

## Approval with Comments
Action that requires comments.

```ruby
class Expense::ApproveService < Expense::BaseService
  performed_action :approve
  with_transaction true

  schema do
    required(:id).filled(:integer)
    required(:approved).filled(:bool)
    optional(:comment).filled(:string, max_size?: 500)
  end

  authorize_with do
    user.can_approve_expenses?
  end

  search_with do
    expense = expense_repository.find(params[:id])

    raise BetterService::Errors::Runtime::ValidationError.new(
      message: "Expense already processed",
      code: :already_processed
    ) unless expense.pending?

    { resource: expense }
  end

  process_with do |data|
    expense = data[:resource]

    if params[:approved]
      expense.approve!(
        approved_by: user,
        approved_at: Time.current,
        comment: params[:comment]
      )
    else
      raise BetterService::Errors::Runtime::ValidationError.new(
        message: "Comment required when rejecting",
        code: :comment_required
      ) if params[:comment].blank?

      expense.reject!(
        rejected_by: user,
        rejected_at: Time.current,
        rejection_reason: params[:comment]
      )
    end

    { resource: expense }
  end
end
```

## Order Fulfillment
Complex order fulfillment action.

```ruby
class Order::FulfillService < Order::BaseService
  performed_action :fulfill
  with_transaction true

  schema do
    required(:id).filled(:integer)
    required(:tracking_number).filled(:string)
    required(:carrier).filled(:string, included_in?: %w[ups fedex usps dhl])
  end

  authorize_with do
    user.warehouse_staff? || user.admin?
  end

  search_with do
    order = order_repository.find(params[:id])

    raise BetterService::Errors::Runtime::ValidationError.new(
      message: "Order not ready for fulfillment",
      code: :not_ready
    ) unless order.can_fulfill?

    { resource: order }
  end

  process_with do |data|
    order = data[:resource]

    # Create shipment
    shipment = Shipment.create!(
      order: order,
      tracking_number: params[:tracking_number],
      carrier: params[:carrier],
      shipped_at: Time.current,
      shipped_by: user
    )

    # Update order
    order.update!(
      status: 'shipped',
      shipment: shipment
    )

    # Notify customer
    OrderMailer.shipped(order).deliver_later

    # Update inventory
    order.line_items.each do |item|
      item.product.decrement!(:stock_count, item.quantity)
    end

    { resource: order, shipment: shipment }
  end
end
```

## Background Job Trigger
Action that triggers a background job.

```ruby
class Report::GenerateLargeExportService < Report::BaseService
  performed_action :generate_large_export

  schema do
    required(:type).filled(:string, included_in?: %w[users orders products])
    optional(:filters).hash do
      optional(:start_date).filled(:date)
      optional(:end_date).filled(:date)
    end
  end

  search_with do
    {}  # No database search needed
  end

  process_with do |_data|
    export = Export.create!(
      type: params[:type],
      filters: params[:filters] || {},
      requested_by: user,
      status: 'queued'
    )

    # Queue background job
    LargeExportJob.perform_later(export.id)

    { resource: export }
  end

  respond_with do |data|
    success_result(
      "Export queued. You'll receive an email when it's ready.",
      data
    )
  end
end
```

## Key Patterns for Custom Actions

### Transaction Usage
- Enable `with_transaction true` for any action that writes to the database
- Omit for read-only actions or external API calls (handle failures differently)

### Action Names
- Use `performed_action :symbol` DSL for meaningful action tracking
- Action name appears in `result[:metadata][:action]`

### Authorization
- Use `authorize_with` for permission checks
- Runs BEFORE search phase for fail-fast behavior

### Error Handling
- Raise appropriate `BetterService::Errors::Runtime` exceptions
- Use `ValidationError` for business rule violations
- Use `ExecutionError` for unexpected failures

### Response Format
```ruby
# All custom actions return:
{
  success: true,
  message: "...",
  resource: object,  # or items: array
  metadata: { action: :action_name }
}
```
