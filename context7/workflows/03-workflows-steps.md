# Workflow Steps Examples

## Step with Service
Basic step definition.

```ruby
class MyWorkflow < BetterService::Workflow
  step :create_order, with: Order::CreateService
  step :charge_payment, with: Payment::ChargeService
  step :send_email, with: Email::ConfirmationService
end
```

## Step with Parameter Mapping
Map context to service parameters.

```ruby
step :charge_payment,
     with: Payment::ChargeService,
     params: ->(context) {
       {
         order_id: context[:order].id,
         amount: context[:order].total,
         payment_method: context[:payment_method]
       }
     }
```

## Conditional Step with if
Execute only when condition is true.

```ruby
step :apply_discount,
     with: Order::ApplyDiscountService,
     if: ->(context) { context[:coupon_code].present? }

step :charge_shipping,
     with: Order::ChargeShippingService,
     if: ->(context) { !context[:order].free_shipping? }

step :send_vip_email,
     with: Email::VipService,
     if: ->(context) { context[:user].vip? && context[:order].total > 500 }
```

## Conditional Step with unless
Execute only when condition is false.

```ruby
step :charge_payment,
     with: Payment::ChargeService,
     unless: ->(context) { context[:order].free? }

step :validate_stock,
     with: Inventory::ValidateService,
     unless: ->(context) { context[:pre_order] }
```

## Step with Error Handler
Log errors without preventing failure.

```ruby
step :charge_payment,
     with: Payment::ChargeService,
     on_error: ->(context, error) {
       PaymentLogger.log_failure(
         order: context[:order],
         error: error.message,
         user: context[:user]
       )

       Sentry.capture_exception(error, extra: {
         order_id: context[:order]&.id
       })

       Metrics.increment('payment.errors')

       # Error still bubbles up and causes rollback
     }
```

## Complex Parameter Extraction
Build complex parameters from context.

```ruby
step :process_payment,
     with: Payment::ProcessService,
     params: ->(context) {
       order = context[:order]

       # Build payment parameters
       params = {
         order_id: order.id,
         amount: order.total,
         currency: order.currency || 'USD'
       }

       # Add payment method details
       case context[:payment_method]
       when 'credit_card'
         params[:card_token] = context[:card_token]
       when 'paypal'
         params[:paypal_email] = context[:paypal_email]
       end

       # Add metadata
       params[:metadata] = {
         user_id: context[:user].id,
         ip_address: context[:ip_address]
       }

       params
     }
```

## Multiple Conditional Steps
Chain multiple conditional steps.

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  # Always execute
  step :create_order, with: Order::CreateService

  # Conditional steps
  step :apply_employee_discount,
       with: Order::EmployeeDiscountService,
       if: ->(context) { context[:user].employee? }

  step :apply_vip_discount,
       with: Order::VipDiscountService,
       if: ->(context) { context[:user].vip? }

  step :apply_coupon,
       with: Order::ApplyCouponService,
       if: ->(context) { context[:coupon_code].present? }

  # Always execute
  step :charge_payment, with: Payment::ChargeService
end
```

## Step Execution Order
Steps execute in definition order.

```ruby
class MyWorkflow < BetterService::Workflow
  step :first, with: FirstService      # 1. Executes first
  step :second, with: SecondService    # 2. Then this
  step :third, with: ThirdService      # 3. Then this
  step :fourth, with: FourthService    # 4. Finally this
end
```

## Using Previous Step Results
Access data from earlier steps.

```ruby
class Order::FulfillmentWorkflow < BetterService::Workflow
  step :create_shipment,
       with: Shipment::CreateService,
       params: ->(context) {
         {
           order_id: context[:order].id
         }
       }

  step :generate_label,
       with: Shipping::GenerateLabelService,
       params: ->(context) {
         {
           shipment_id: context[:shipment].id,  # From previous step
           carrier: 'fedex'
         }
       }

  step :send_tracking,
       with: Email::TrackingService,
       params: ->(context) {
         {
           user_id: context[:order].user_id,
           tracking_number: context[:label].tracking_number  # From previous step
         }
       }
end
```

## Computed Conditions
Complex conditional logic.

```ruby
step :apply_rush_delivery,
     with: Order::RushDeliveryService,
     if: ->(context) {
       order = context[:order]

       # Complex condition
       is_eligible = order.total > 100 &&
                     order.created_at > 1.hour.ago &&
                     order.shipping_address.country == 'US'

       context[:rush_requested] && is_eligible
     }
```

## Default Parameter Values
Provide defaults in parameter mapping.

```ruby
step :configure_settings,
     with: Settings::ConfigureService,
     params: ->(context) {
       {
         user_id: context[:user].id,
         locale: context[:locale] || 'en',
         timezone: context[:timezone] || 'UTC',
         currency: context[:currency] || 'USD',
         theme: context[:theme] || 'light'
       }
     }
```
