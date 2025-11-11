# ActionService

## Overview

ActionService is the most flexible service type, designed for custom business operations that don't fit the standard CRUD pattern. It can be configured for read-only or transactional operations and supports custom action names.

**Characteristics:**
- **Action**: Custom (you define it)
- **Transaction**: Configurable (ON/OFF)
- **Return Key**: `resource` (or custom)
- **Default Schema**: None (you define it)
- **Common Use Cases**: State transitions, batch operations, external integrations, complex workflows

## Generation

### Basic Generation

```bash
rails g serviceable:action Order Approve
```

This generates:

```ruby
# app/services/order/approve_service.rb
module Order
  class ApproveService < BetterService::ActionService
    model_class Order
    action_name :approve

    schema do
      required(:id).filled(:integer)
      # Add your custom parameters
    end

    search_with do
      resource = model_class.find(params[:id])
      { resource: resource }
    end

    process_with do |data|
      resource = data[:resource]

      # Your custom business logic here
      resource.update!(status: 'approved', approved_at: Time.current)

      { resource: resource }
    end
  end
end
```

### Generation with Options

```bash
# With transaction enabled
rails g serviceable:action Payment Process --transaction

# With cache invalidation
rails g serviceable:action Report Generate --cache

# Multiple actions
rails g serviceable:action Order Approve Cancel Refund
```

## Configuration

### Action Name

Define the custom action identifier:

```ruby
class Order::ApproveService < BetterService::ActionService
  action_name :approve  # Used in metadata[:action] => :approve
end
```

### Transaction Control

```ruby
# Enable transactions (for write operations)
class Order::ProcessService < BetterService::ActionService
  action_name :process
  self._transactional = true

  process_with do |data|
    # All operations in transaction
    order = data[:resource]
    order.update!(status: 'processing')
    Payment.charge!(order)
    Inventory.reserve!(order.items)
    { resource: order }
  end
end

# Disable transactions (for read operations)
class Report::GenerateService < BetterService::ActionService
  action_name :generate
  self._transactional = false

  process_with do |data|
    # No transaction needed for read-only
    { resource: generate_report_data }
  end
end
```

### Cache Configuration

```ruby
class Product::PublishService < BetterService::ActionService
  action_name :publish
  cache_contexts :products, :published_products

  process_with do |data|
    resource = data[:resource]
    resource.publish!

    invalidate_cache_for(user)

    { resource: resource }
  end
end
```

## Complete Examples

### Example 1: Order Approval

```ruby
module Order
  class ApproveService < BetterService::ActionService
    model_class Order
    action_name :approve
    cache_contexts :orders, :pending_orders

    self._transactional = true

    schema do
      required(:id).filled(:integer)
      optional(:notes).maybe(:string)
    end

    authorize_with do
      resource = model_class.find(params[:id])

      # Only managers can approve orders
      user.manager? || user.admin?
    end

    search_with do
      order = model_class.includes(:items, :user).find(params[:id])

      # Validate order can be approved
      unless order.pending?
        raise BetterService::Errors::Runtime::ValidationError.new(
          "Only pending orders can be approved"
        )
      end

      # Check inventory
      order.items.each do |item|
        if item.product.stock < item.quantity
          raise BetterService::Errors::Runtime::ValidationError.new(
            "Insufficient stock for #{item.product.name}"
          )
        end
      end

      { resource: order }
    end

    process_with do |data|
      order = data[:resource]

      # Update order status
      order.update!(
        status: 'approved',
        approved_at: Time.current,
        approved_by_id: user.id,
        approval_notes: params[:notes]
      )

      # Reserve inventory
      order.items.each do |item|
        item.product.decrement!(:stock, item.quantity)
      end

      # Create fulfillment
      Fulfillment.create!(
        order: order,
        status: 'pending'
      )

      # Send notifications
      OrderMailer.approved(order).deliver_later
      SlackNotifier.notify_fulfillment_team(order).deliver_later

      invalidate_cache_for(user)
      invalidate_cache_for(order.user)

      { resource: order }
    end

    respond_with do |data|
      success_result("Order ##{data[:resource].id} approved successfully", data)
    end
  end
end

# Usage
result = Order::ApproveService.new(current_user, params: {
  id: 789,
  notes: "All items in stock, ready to ship"
}).call

order = result[:resource]
# => #<Order id: 789, status: "approved", ...>
```

### Example 2: Article Publishing

```ruby
module Article
  class PublishService < BetterService::ActionService
    model_class Article
    action_name :publish
    cache_contexts :articles, :published_articles

    self._transactional = true

    schema do
      required(:id).filled(:integer)
      optional(:publish_at).maybe(:time)
      optional(:notify_subscribers).maybe(:bool)
    end

    authorize_with do
      article = model_class.find(params[:id])

      # Authors can publish own articles, editors can publish any
      article.author_id == user.id || user.editor? || user.admin?
    end

    search_with do
      article = model_class.includes(:tags, :images).find(params[:id])

      # Validate article is ready for publishing
      if article.published?
        raise BetterService::Errors::Runtime::ValidationError.new(
          "Article is already published"
        )
      end

      unless article.title.present? && article.content.present?
        raise BetterService::Errors::Runtime::ValidationError.new(
          "Title and content are required"
        )
      end

      if article.images.blank? && !params[:skip_image_check]
        raise BetterService::Errors::Runtime::ValidationError.new(
          "Featured image is required"
        )
      end

      { resource: article }
    end

    process_with do |data|
      article = data[:resource]
      publish_time = params[:publish_at] || Time.current

      # Update article
      article.update!(
        status: 'published',
        published_at: publish_time,
        published_by_id: user.id
      )

      # Generate slug if not present
      if article.slug.blank?
        article.update!(slug: generate_slug(article.title, article.id))
      end

      # Update author stats
      article.author.increment!(:published_articles_count)

      # Schedule notifications
      if params[:notify_subscribers] != false
        if publish_time > Time.current
          # Schedule for future
          NotifySubscribersJob.set(wait_until: publish_time).perform_later(article.id)
        else
          # Send immediately
          NotifySubscribersJob.perform_later(article.id)
        end
      end

      # Submit to search engine
      SearchIndexJob.perform_later('Article', article.id)

      # Track event
      Analytics.track('article_published', {
        article_id: article.id,
        author_id: article.author_id,
        publish_at: publish_time
      })

      invalidate_cache_for(user)

      { resource: article }
    end

    respond_with do |data|
      article = data[:resource]
      scheduled = params[:publish_at] && params[:publish_at] > Time.current

      message = scheduled ?
        "Article scheduled for #{params[:publish_at].strftime('%B %d, %Y at %I:%M %p')}" :
        "Article published successfully"

      success_result(message, data).merge(
        url: article_url(article)
      )
    end

    private

    def generate_slug(title, id)
      "#{title.parameterize}-#{id}"
    end

    def article_url(article)
      Rails.application.routes.url_helpers.article_url(article.slug)
    end
  end
end

# Usage
result = Article::PublishService.new(current_user, params: {
  id: 123,
  publish_at: 2.hours.from_now,
  notify_subscribers: true
}).call
```

### Example 3: Payment Processing

```ruby
module Payment
  class ProcessService < BetterService::ActionService
    model_class Payment
    action_name :process
    cache_contexts :payments

    self._transactional = true

    schema do
      required(:order_id).filled(:integer)
      required(:payment_method).filled(:string, included_in?: %w[credit_card paypal stripe])
      required(:amount).filled(:decimal, gt?: 0)

      optional(:card_token).maybe(:string)
      optional(:save_card).maybe(:bool)
    end

    authorize_with do
      order = Order.find(params[:order_id])
      order.user_id == user.id || user.admin?
    end

    search_with do
      order = Order.includes(:user, :items).find(params[:order_id])

      # Validate order status
      unless order.pending_payment?
        raise BetterService::Errors::Runtime::ValidationError.new(
          "Order is not pending payment"
        )
      end

      # Validate amount
      unless params[:amount] == order.total
        raise BetterService::Errors::Runtime::ValidationError.new(
          "Payment amount does not match order total"
        )
      end

      { order: order }
    end

    process_with do |data|
      order = data[:order]

      # Create payment record
      payment = Payment.create!(
        order: order,
        user: user,
        amount: params[:amount],
        payment_method: params[:payment_method],
        status: 'processing'
      )

      begin
        # Process payment through gateway
        result = case params[:payment_method]
        when 'credit_card'
          process_credit_card(payment, params[:card_token])
        when 'paypal'
          process_paypal(payment)
        when 'stripe'
          process_stripe(payment, params[:card_token])
        end

        # Update payment
        payment.update!(
          status: 'completed',
          transaction_id: result[:transaction_id],
          processed_at: Time.current
        )

        # Update order
        order.update!(
          status: 'paid',
          paid_at: Time.current
        )

        # Save card if requested
        if params[:save_card] && params[:card_token]
          save_payment_method(user, result[:card_details])
        end

        # Send confirmation
        PaymentMailer.confirmation(payment).deliver_later
        OrderMailer.payment_received(order).deliver_later

        # Track conversion
        Analytics.track('payment_completed', {
          order_id: order.id,
          amount: params[:amount],
          method: params[:payment_method]
        })

      rescue PaymentGatewayError => e
        # Mark payment as failed
        payment.update!(
          status: 'failed',
          error_message: e.message
        )

        # Notify user
        PaymentMailer.failed(payment).deliver_later

        raise BetterService::Errors::Runtime::ExecutionError.new(
          "Payment processing failed: #{e.message}"
        )
      end

      invalidate_cache_for(user)

      { resource: payment, order: order }
    end

    private

    def process_credit_card(payment, token)
      # Integration with payment gateway
      gateway = PaymentGateway.new
      gateway.charge(
        amount: payment.amount,
        token: token,
        description: "Order ##{payment.order_id}"
      )
    end

    def process_stripe(payment, token)
      Stripe::Charge.create(
        amount: (payment.amount * 100).to_i, # cents
        currency: 'usd',
        source: token,
        description: "Order ##{payment.order_id}"
      )
    end

    def process_paypal(payment)
      # PayPal integration
      PayPalService.charge(payment)
    end

    def save_payment_method(user, card_details)
      user.payment_methods.create!(
        card_last4: card_details[:last4],
        card_brand: card_details[:brand],
        card_exp_month: card_details[:exp_month],
        card_exp_year: card_details[:exp_year]
      )
    end
  end
end

# Usage
result = Payment::ProcessService.new(current_user, params: {
  order_id: 456,
  payment_method: 'stripe',
  amount: 299.99,
  card_token: 'tok_visa',
  save_card: true
}).call

payment = result[:resource]
order = result[:order]
```

### Example 4: Batch Operations

```ruby
module Product
  class ImportFromCSVService < BetterService::ActionService
    action_name :import_csv
    cache_contexts :products

    self._transactional = true

    schema do
      required(:csv_file).filled(:hash)
      optional(:update_existing).maybe(:bool)
      optional(:skip_errors).maybe(:bool)
    end

    authorize_with do
      user.admin? || user.has_permission?(:import_products)
    end

    search_with do
      # Parse CSV
      csv_data = parse_csv(params[:csv_file])

      # Validate CSV structure
      validate_csv_headers(csv_data)

      { csv_data: csv_data }
    end

    process_with do |data|
      rows = data[:csv_data]

      results = {
        created: [],
        updated: [],
        skipped: [],
        errors: []
      }

      rows.each_with_index do |row, index|
        begin
          # Find existing product by SKU
          product = Product.find_by(sku: row[:sku])

          if product
            if params[:update_existing]
              # Update existing
              product.update!(
                name: row[:name],
                price: row[:price],
                description: row[:description]
              )
              results[:updated] << product.id
            else
              results[:skipped] << { row: index + 1, sku: row[:sku], reason: 'already exists' }
            end
          else
            # Create new
            product = Product.create!(
              sku: row[:sku],
              name: row[:name],
              price: row[:price],
              description: row[:description],
              category_id: find_category_id(row[:category]),
              user: user
            )
            results[:created] << product.id
          end

        rescue => e
          if params[:skip_errors]
            results[:errors] << {
              row: index + 1,
              sku: row[:sku],
              error: e.message
            }
          else
            raise BetterService::Errors::Runtime::ExecutionError.new(
              "Error on row #{index + 1}: #{e.message}"
            )
          end
        end
      end

      invalidate_cache_for(user)

      {
        resource: results,
        metadata: {
          total_rows: rows.count,
          created_count: results[:created].count,
          updated_count: results[:updated].count,
          skipped_count: results[:skipped].count,
          error_count: results[:errors].count
        }
      }
    end

    respond_with do |data|
      meta = data[:metadata]
      message = "Import completed: #{meta[:created_count]} created, " \
                "#{meta[:updated_count]} updated, #{meta[:error_count]} errors"

      success_result(message, data)
    end

    private

    def parse_csv(file)
      require 'csv'
      CSV.parse(file[:tempfile].read, headers: true, header_converters: :symbol)
    end

    def validate_csv_headers(csv)
      required_headers = [:sku, :name, :price]
      headers = csv.headers

      missing = required_headers - headers
      if missing.any?
        raise BetterService::Errors::Runtime::ValidationError.new(
          "Missing required headers: #{missing.join(', ')}"
        )
      end
    end

    def find_category_id(category_name)
      return nil if category_name.blank?
      Category.find_or_create_by!(name: category_name).id
    end
  end
end

# Usage
result = Product::ImportFromCSVService.new(current_user, params: {
  csv_file: uploaded_file,
  update_existing: true,
  skip_errors: true
}).call

puts result[:metadata]
# => {
#   total_rows: 100,
#   created_count: 75,
#   updated_count: 20,
#   skipped_count: 0,
#   error_count: 5
# }
```

## Best Practices

### 1. Choose the Right Transaction Setting

```ruby
# Write operations: Enable transactions
class Order::ProcessService < BetterService::ActionService
  self._transactional = true  # ✅
end

# Read operations: Disable transactions
class Report::GenerateService < BetterService::ActionService
  self._transactional = false  # ✅
end
```

### 2. Use Meaningful Action Names

```ruby
# ✅ Good: Clear, verb-based action names
action_name :approve
action_name :publish
action_name :cancel
action_name :archive

# ❌ Bad: Generic or unclear names
action_name :do_stuff
action_name :handle
action_name :execute
```

### 3. Validate State Transitions

```ruby
search_with do
  resource = model_class.find(params[:id])

  # Check current state allows this action
  unless resource.can_transition_to?(:approved)
    raise BetterService::Errors::Runtime::ValidationError.new(
      "Cannot approve #{resource.status} order"
    )
  end

  { resource: resource }
end
```

### 4. Use External Service Wrappers

```ruby
process_with do |data|
  begin
    # Wrap external service calls
    result = ExternalService.call_api(params)
  rescue ExternalService::Error => e
    # Convert to BetterService error
    raise BetterService::Errors::Runtime::ExecutionError.new(
      "External service failed: #{e.message}"
    )
  end

  { resource: result }
end
```

### 5. Track Analytics for Business Actions

```ruby
process_with do |data|
  resource = data[:resource]

  # Perform action
  resource.approve!

  # Track important business events
  Analytics.track('order_approved', {
    order_id: resource.id,
    approved_by: user.id,
    value: resource.total
  })

  { resource: resource }
end
```

### 6. Return Rich Metadata

```ruby
respond_with do |data|
  success_result("Operation completed", data).merge(
    summary: generate_summary(data),
    next_steps: suggest_next_steps(data),
    warnings: check_for_warnings(data)
  )
end
```

## Testing

### RSpec

```ruby
# spec/services/order/approve_service_spec.rb
require 'rails_helper'

RSpec.describe Order::ApproveService do
  let(:manager) { create(:user, :manager) }
  let(:order) { create(:order, :pending) }

  describe '#call' do
    it 'approves the order' do
      result = described_class.new(manager, params: { id: order.id }).call

      expect(result[:success]).to be true
      expect(order.reload.status).to eq('approved')
      expect(order.approved_at).to be_present
      expect(order.approved_by).to eq(manager)
    end

    it 'reserves inventory' do
      item = create(:order_item, order: order, quantity: 5)

      expect {
        described_class.new(manager, params: { id: order.id }).call
      }.to change { item.product.reload.stock }.by(-5)
    end

    it 'sends notifications' do
      expect {
        described_class.new(manager, params: { id: order.id }).call
      }.to have_enqueued_job(ActionMailer::MailDeliveryJob)
    end

    context 'when order cannot be approved' do
      let(:order) { create(:order, :completed) }

      it 'raises validation error' do
        expect {
          described_class.new(manager, params: { id: order.id }).call
        }.to raise_error(BetterService::Errors::Runtime::ValidationError)
      end
    end

    context 'with insufficient stock' do
      it 'raises validation error' do
        item = create(:order_item, order: order, quantity: 100)
        item.product.update!(stock: 5)

        expect {
          described_class.new(manager, params: { id: order.id }).call
        }.to raise_error(BetterService::Errors::Runtime::ValidationError, /insufficient stock/i)
      end
    end

    context 'authorization' do
      let(:regular_user) { create(:user) }

      it 'allows managers to approve' do
        expect {
          described_class.new(manager, params: { id: order.id }).call
        }.not_to raise_error
      end

      it 'denies regular users' do
        expect {
          described_class.new(regular_user, params: { id: order.id }).call
        }.to raise_error(BetterService::Errors::Runtime::AuthorizationError)
      end
    end
  end
end
```

### Minitest

```ruby
# test/services/order/approve_service_test.rb
require 'test_helper'

class Order::ApproveServiceTest < ActiveSupport::TestCase
  setup do
    @manager = users(:manager)
    @order = orders(:pending_order)
  end

  test "approves the order" do
    Order::ApproveService.new(@manager, params: { id: @order.id }).call

    assert_equal 'approved', @order.reload.status
    assert_not_nil @order.approved_at
    assert_equal @manager, @order.approved_by
  end

  test "reserves inventory" do
    item = @order.items.first
    original_stock = item.product.stock

    Order::ApproveService.new(@manager, params: { id: @order.id }).call

    assert_equal original_stock - item.quantity, item.product.reload.stock
  end

  test "raises error for non-pending orders" do
    @order.update!(status: 'completed')

    assert_raises BetterService::Errors::Runtime::ValidationError do
      Order::ApproveService.new(@manager, params: { id: @order.id }).call
    end
  end

  test "denies regular users" do
    regular_user = users(:regular)

    assert_raises BetterService::Errors::Runtime::AuthorizationError do
      Order::ApproveService.new(regular_user, params: { id: @order.id }).call
    end
  end
end
```

## Common Use Cases

### State Machines

```ruby
# Archive, Activate, Suspend, etc.
class User::SuspendService < BetterService::ActionService
  action_name :suspend
  # ...
end
```

### External Integrations

```ruby
# Sync, Export, Import, etc.
class Product::SyncToShopifyService < BetterService::ActionService
  action_name :sync_to_shopify
  # ...
end
```

### Batch Operations

```ruby
# BulkArchive, BulkUpdate, BatchProcess, etc.
class Email::SendBulkService < BetterService::ActionService
  action_name :send_bulk
  # ...
end
```

### Report Generation

```ruby
# Generate, Export, Compile, etc.
class Report::GenerateMonthlyService < BetterService::ActionService
  action_name :generate_monthly
  self._transactional = false
  # ...
end
```

---

**See also:**
- [Services Structure](01_services_structure.md)
- [Service Configurations](08_service_configurations.md)
- [Workflows](../workflows/01_workflows_introduction.md)
- [Error Handling](../advanced/error-handling.md)
