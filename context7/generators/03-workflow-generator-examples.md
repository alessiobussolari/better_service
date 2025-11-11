# Workflow Generators Examples

## Generate Basic Workflow
Create a new workflow file.

```bash
rails g serviceable:workflow Order::Checkout
```

Creates: `app/workflows/order/checkout_workflow.rb`
```ruby
module Order
  class CheckoutWorkflow < BetterService::Workflow
    schema do
      # Define your parameters here
    end

    # Add steps here
    step :step_one, with: StepOneService
    step :step_two, with: StepTwoService
  end
end
```

## Generate with Namespace
Create workflow in nested module.

```bash
rails g serviceable:workflow Admin::Report::Generate
```

Creates: `app/workflows/admin/report/generate_workflow.rb`
```ruby
module Admin
  module Report
    class GenerateWorkflow < BetterService::Workflow
      schema do
        # Define your parameters
      end

      step :first_step, with: FirstStepService
    end
  end
end
```

## Complete Checkout Workflow
Multi-step e-commerce checkout.

```bash
rails g serviceable:workflow Order::Checkout
```

Then edit to add steps:
```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  schema do
    required(:cart_id).filled(:integer)
    required(:payment_method).filled(:string)
  end

  step :create_order, with: Order::CreateService
  step :charge_payment, with: Payment::ChargeService
  step :clear_cart, with: Cart::ClearService
  step :send_confirmation, with: Email::ConfirmationService
end
```

## Registration Workflow
User registration with multiple steps.

```bash
rails g serviceable:workflow User::Registration
```

Implementation:
```ruby
class User::RegistrationWorkflow < BetterService::Workflow
  self._allow_nil_user = true

  schema do
    required(:email).filled(:string)
    required(:password).filled(:string)
  end

  step :create_user, with: User::CreateService
  step :create_profile, with: Profile::CreateService
  step :send_welcome, with: Email::WelcomeService
  step :send_verification, with: Email::VerificationService
end
```

## Payment Processing Workflow
Process payment with validations.

```bash
rails g serviceable:workflow Payment::Process
```

Implementation:
```ruby
class Payment::ProcessWorkflow < BetterService::Workflow
  schema do
    required(:order_id).filled(:integer)
    required(:card_token).filled(:string)
  end

  step :validate_card, with: Payment::ValidateCardService
  step :charge_payment, with: Payment::ChargeService
  step :update_order, with: Order::UpdateStatusService
  step :send_receipt, with: Email::ReceiptService
end
```

## Import Workflow
Multi-step data import process.

```bash
rails g serviceable:workflow Import::CSV
```

Implementation:
```ruby
class Import::CSVWorkflow < BetterService::Workflow
  schema do
    required(:file).filled(:hash)
    required(:model_type).filled(:string)
  end

  step :validate_file, with: Import::ValidateFileService
  step :parse_csv, with: Import::ParseCSVService
  step :create_import_record, with: Import::CreateRecordService
  step :process_rows, with: Import::ProcessRowsService
  step :generate_report, with: Import::GenerateReportService
end
```

## Publishing Workflow
Content publishing with SEO.

```bash
rails g serviceable:workflow Article::Publish
```

Implementation:
```ruby
class Article::PublishWorkflow < BetterService::Workflow
  schema do
    required(:article_id).filled(:integer)
  end

  step :validate_article, with: Article::ValidateService
  step :generate_seo, with: Article::GenerateSEOService
  step :optimize_images, with: Article::OptimizeImagesService
  step :publish_article, with: Article::PublishService
  step :index_search, with: Article::IndexSearchService
end
```

## Refund Workflow
Order refund with inventory restock.

```bash
rails g serviceable:workflow Order::Refund
```

Implementation:
```ruby
class Order::RefundWorkflow < BetterService::Workflow
  schema do
    required(:order_id).filled(:integer)
    required(:reason).filled(:string)
  end

  step :validate_refund, with: Order::ValidateRefundService
  step :calculate_refund, with: Payment::CalculateRefundService
  step :process_refund, with: Payment::ProcessRefundService
  step :restock_items, with: Inventory::RestockService
  step :send_confirmation, with: Email::RefundConfirmationService
end
```

## Onboarding Workflow
Multi-tenant customer onboarding.

```bash
rails g serviceable:workflow Tenant::Onboard
```

Implementation:
```ruby
class Tenant::OnboardWorkflow < BetterService::Workflow
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

## Workflow with Conditional Steps
Steps that execute conditionally.

```bash
rails g serviceable:workflow Order::Checkout
```

With conditional logic:
```ruby
class Order::CheckoutWorkflow < BetterService::Workflow
  schema do
    required(:cart_id).filled(:integer)
    optional(:coupon_code).maybe(:string)
  end

  step :create_order, with: Order::CreateService

  step :apply_coupon,
       with: Order::ApplyCouponService,
       if: ->(context) { context[:coupon_code].present? }

  step :charge_payment, with: Payment::ChargeService
  step :send_confirmation, with: Email::ConfirmationService
end
```
