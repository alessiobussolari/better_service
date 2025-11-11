# Workflow Patterns Examples

## E-Commerce Checkout
Complete checkout with payment and email.

```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  schema do
    required(:cart_id).filled(:integer)
    required(:payment_method).filled(:string)
    required(:shipping_address).hash
  end

  step :create_order, with: Order::CreateFromCartService
  step :apply_coupon,
       with: Order::ApplyCouponService,
       if: ->(context) { context[:coupon_code].present? }
  step :calculate_shipping, with: Order::CalculateShippingService
  step :charge_payment, with: Payment::ChargeService
  step :confirm_order, with: Order::ConfirmService
  step :clear_cart, with: Cart::ClearService
  step :send_confirmation, with: Email::OrderConfirmationService
end
```

## User Registration
Create user with profile and send emails.

```ruby
class User::RegistrationWorkflow < BetterService::Workflow
  self._allow_nil_user = true

  schema do
    required(:email).filled(:string, format?: /@/)
    required(:password).filled(:string, min_size?: 8)
    required(:first_name).filled(:string)
    required(:last_name).filled(:string)
  end

  step :validate_email, with: User::ValidateEmailService
  step :create_user, with: User::CreateService
  step :create_profile, with: Profile::CreateService
  step :generate_token, with: User::GenerateVerificationTokenService
  step :send_welcome, with: Email::WelcomeService
  step :send_verification, with: Email::VerificationService
end
```

## Article Publishing
Validate, optimize, and publish content.

```ruby
class Article::PublishingWorkflow < BetterService::Workflow
  schema do
    required(:article_id).filled(:integer)
    optional(:publish_at).maybe(:time)
    optional(:notify_subscribers).maybe(:bool)
  end

  step :validate_article, with: Article::ValidateService
  step :generate_seo, with: Article::GenerateSEOService
  step :optimize_images, with: Article::OptimizeImagesService
  step :publish_article, with: Article::PublishService
  step :index_search, with: Article::IndexSearchService
  step :notify_subscribers,
       with: Article::NotifySubscribersService,
       if: ->(context) { context[:notify_subscribers] != false }
end
```

## Payment Refund
Validate, refund, and notify.

```ruby
class Payment::RefundWorkflow < BetterService::Workflow
  schema do
    required(:order_id).filled(:integer)
    required(:reason).filled(:string)
  end

  step :validate_refund, with: Payment::ValidateRefundService
  step :calculate_refund, with: Payment::CalculateRefundService
  step :process_refund, with: Payment::ProcessRefundService
  step :update_order, with: Order::UpdateStatusService
  step :restock_items, with: Inventory::RestockService
  step :send_confirmation, with: Email::RefundConfirmationService
end
```

## Data Import
Parse, validate, and import CSV data.

```ruby
class Import::CSVImportWorkflow < BetterService::Workflow
  schema do
    required(:file).filled(:hash)
    required(:model_type).filled(:string)
  end

  step :validate_file, with: Import::ValidateFileService
  step :parse_csv, with: Import::ParseCSVService
  step :validate_headers, with: Import::ValidateHeadersService
  step :create_import_record, with: Import::CreateRecordService
  step :process_rows, with: Import::ProcessRowsService
  step :generate_report, with: Import::GenerateReportService
  step :send_notification, with: Email::ImportCompletionService
end
```

## Multi-Tenant Onboarding
Setup new tenant with resources.

```ruby
class Tenant::OnboardingWorkflow < BetterService::Workflow
  schema do
    required(:company_name).filled(:string)
    required(:admin_email).filled(:string)
  end

  step :create_tenant, with: Tenant::CreateService
  step :create_admin, with: User::CreateAdminService
  step :setup_billing, with: Billing::SetupService
  step :create_sample_data, with: SampleData::CreateService
  step :send_welcome, with: Email::TenantWelcomeService
end
```

## Invoice Generation
Calculate, generate, and deliver invoice.

```ruby
class Invoice::GenerationWorkflow < BetterService::Workflow
  schema do
    required(:order_id).filled(:integer)
  end

  step :validate_order, with: Invoice::ValidateOrderService
  step :calculate_totals, with: Invoice::CalculateTotalsService
  step :generate_pdf, with: Invoice::GeneratePDFService
  step :store_invoice, with: Invoice::StoreService
  step :send_invoice, with: Email::InvoiceService
end
```

## Subscription Cancellation
Cancel, refund, and cleanup subscription.

```ruby
class Subscription::CancellationWorkflow < BetterService::Workflow
  schema do
    required(:subscription_id).filled(:integer)
    optional(:reason).maybe(:string)
    optional(:immediate).maybe(:bool)
  end

  step :validate_cancellation, with: Subscription::ValidateCancellationService
  step :calculate_refund,
       with: Subscription::CalculateRefundService,
       if: ->(context) { context[:immediate] }
  step :process_refund,
       with: Payment::RefundService,
       if: ->(context) { context[:refund_amount].to_f > 0 }
  step :cancel_subscription, with: Subscription::CancelService
  step :revoke_access, with: Access::RevokeService
  step :send_confirmation, with: Email::CancellationConfirmationService
end
```
