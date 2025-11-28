# Workflow Examples

## Overview

This guide provides real-world workflow examples for common business processes, demonstrating patterns, best practices, and advanced techniques.

---

## E-Commerce: Order Checkout

### Complete Checkout Flow

```ruby
# app/workflows/order/checkout_workflow.rb
module Order
  class CheckoutWorkflow < BetterService::Workflow
    schema do
      required(:cart_id).filled(:integer)
      required(:payment_method).filled(:string, included_in?: %w[credit_card paypal stripe])
      required(:shipping_address).hash do
        required(:street).filled(:string)
        required(:city).filled(:string)
        required(:zip).filled(:string)
        required(:country).filled(:string)
      end

      optional(:coupon_code).maybe(:string)
      optional(:gift_message).maybe(:string)
      optional(:save_payment_method).maybe(:bool)
    end

    authorize_with do
      user.active? && !user.banned?
    end

    # Step 1: Validate cart and create order
    step :create_order,
         with: Order::CreateFromCartService,
         params: ->(context) {
           {
             cart_id: context[:cart_id],
             shipping_address: context[:shipping_address],
             gift_message: context[:gift_message]
           }
         }

    # Step 2: Apply coupon if provided
    step :apply_coupon,
         with: Order::ApplyCouponService,
         if: ->(context) { context[:coupon_code].present? },
         params: ->(context) {
           {
             order_id: context[:order].id,
             coupon_code: context[:coupon_code]
           }
         }

    # Step 3: Calculate shipping cost
    step :calculate_shipping,
         with: Order::CalculateShippingService,
         params: ->(context) {
           {
             order_id: context[:order].id,
             address: context[:shipping_address]
           }
         }

    # Step 4: Calculate taxes
    step :calculate_taxes,
         with: Order::CalculateTaxesService,
         params: ->(context) {
           {
             order_id: context[:order].id,
             address: context[:shipping_address]
           }
         }

    # Step 5: Validate inventory
    step :validate_inventory,
         with: Inventory::ValidateService,
         params: ->(context) {
           {
             order_id: context[:order].id
           }
         }

    # Step 6: Charge payment
    step :charge_payment,
         with: Payment::ChargeService,
         params: ->(context) {
           order = context[:order].reload
           {
             order_id: order.id,
             amount: order.total,
             payment_method: context[:payment_method],
             save_payment_method: context[:save_payment_method]
           }
         },
         on_error: ->(context, error) {
           PaymentLogger.log_failure(context[:order], error)
           Metrics.increment('payment.failures')
         }

    # Step 7: Confirm order
    step :confirm_order,
         with: Order::ConfirmService,
         params: ->(context) {
           {
             order_id: context[:order].id,
             payment_id: context[:payment].id
           }
         }

    # Step 8: Reserve inventory
    step :reserve_inventory,
         with: Inventory::ReserveService,
         params: ->(context) {
           {
             order_id: context[:order].id
           }
         }

    # Step 9: Clear cart
    step :clear_cart,
         with: Cart::ClearService,
         params: ->(context) {
           {
             cart_id: context[:cart_id]
           }
         }

    # Step 10: Send confirmation email
    step :send_confirmation,
         with: Email::OrderConfirmationService,
         params: ->(context) {
           {
             order_id: context[:order].id
           }
         }

    # Step 11: Track conversion
    step :track_conversion,
         with: Analytics::TrackConversionService,
         params: ->(context) {
           {
             user_id: user.id,
             order_id: context[:order].id,
             revenue: context[:order].total
           }
         }

    def after_execution(result)
      logger.info "Checkout completed: Order ##{result[:order].id}"
      Metrics.increment('checkout.completed')
    end

    def on_workflow_error(error)
      logger.error "Checkout failed: #{error.message}"
      Metrics.increment('checkout.failed')
    end
  end
end

# Usage
result = Order::CheckoutWorkflow.new(current_user, params: {
  cart_id: cart.id,
  payment_method: 'credit_card',
  shipping_address: {
    street: "123 Main St",
    city: "New York",
    zip: "10001",
    country: "USA"
  },
  coupon_code: "SAVE20"
}).call

redirect_to order_path(result[:order])
```

---

## User Management: Registration

### Complete Registration Flow

```ruby
# app/workflows/user/registration_workflow.rb
module User
  class RegistrationWorkflow < BetterService::Workflow
    self._allow_nil_user = true  # No user exists yet

    schema do
      required(:email).filled(:string, format?: /@/)
      required(:password).filled(:string, min_size?: 8)
      required(:password_confirmation).filled(:string)
      required(:first_name).filled(:string)
      required(:last_name).filled(:string)

      optional(:company_name).maybe(:string)
      optional(:phone).maybe(:string)
      optional(:referral_code).maybe(:string)
      optional(:newsletter).maybe(:bool)

      rule(:password, :password_confirmation) do
        if values[:password] != values[:password_confirmation]
          key(:password_confirmation).failure('must match password')
        end
      end
    end

    # Step 1: Validate email availability
    step :validate_email,
         with: User::ValidateEmailService,
         params: ->(context) {
           {
             email: context[:email]
           }
         }

    # Step 2: Process referral code if provided
    step :validate_referral,
         with: User::ValidateReferralService,
         if: ->(context) { context[:referral_code].present? },
         params: ->(context) {
           {
             referral_code: context[:referral_code]
           }
         }

    # Step 3: Create user account
    step :create_user,
         with: User::CreateService,
         params: ->(context) {
           {
             email: context[:email].downcase,
             password: context[:password],
             first_name: context[:first_name],
             last_name: context[:last_name],
             company_name: context[:company_name],
             phone: context[:phone]
           }
         }

    # Step 4: Apply referral bonus
    step :apply_referral_bonus,
         with: User::ApplyReferralBonusService,
         if: ->(context) { context[:referral].present? },
         params: ->(context) {
           {
             user_id: context[:user].id,
             referrer_id: context[:referral].referrer_id
           }
         }

    # Step 5: Create user profile
    step :create_profile,
         with: Profile::CreateService,
         params: ->(context) {
           {
             user_id: context[:user].id
           }
         }

    # Step 6: Setup default preferences
    step :setup_preferences,
         with: Preferences::CreateService,
         params: ->(context) {
           {
             user_id: context[:user].id,
             newsletter: context[:newsletter]
           }
         }

    # Step 7: Generate verification token
    step :generate_token,
         with: User::GenerateVerificationTokenService,
         params: ->(context) {
           {
             user_id: context[:user].id
           }
         }

    # Step 8: Create sample data for demo
    step :create_sample_data,
         with: SampleData::CreateService,
         params: ->(context) {
           {
             user_id: context[:user].id
           }
         }

    # Step 9: Send welcome email
    step :send_welcome,
         with: Email::WelcomeService,
         params: ->(context) {
           {
             user_id: context[:user].id
           }
         }

    # Step 10: Send verification email
    step :send_verification,
         with: Email::VerificationService,
         params: ->(context) {
           {
             user_id: context[:user].id,
             token: context[:verification_token]
           }
         }

    # Step 11: Subscribe to newsletter
    step :subscribe_newsletter,
         with: Newsletter::SubscribeService,
         if: ->(context) { context[:newsletter] == true },
         params: ->(context) {
           {
             email: context[:user].email,
             name: context[:user].full_name
           }
         }

    # Step 12: Track signup
    step :track_signup,
         with: Analytics::TrackSignupService,
         params: ->(context) {
           {
             user_id: context[:user].id,
             referral_code: context[:referral_code]
           }
         }

    def after_execution(result)
      Metrics.increment('user.registrations')
    end
  end
end

# Usage
result = User::RegistrationWorkflow.new(nil, params: {
  email: "john@example.com",
  password: "SecurePass123",
  password_confirmation: "SecurePass123",
  first_name: "John",
  last_name: "Doe",
  referral_code: "FRIEND20",
  newsletter: true
}).call

session[:user_id] = result[:user].id
redirect_to dashboard_path
```

---

## Content Publishing: Article Workflow

### Article Publishing Flow

```ruby
# app/workflows/article/publishing_workflow.rb
module Article
  class PublishingWorkflow < BetterService::Workflow
    schema do
      required(:article_id).filled(:integer)
      optional(:publish_at).maybe(:time)
      optional(:notify_subscribers).maybe(:bool)
      optional(:share_on_social).maybe(:bool)
      optional(:featured).maybe(:bool)
    end

    authorize_with do
      article = Article.find(params[:article_id])
      article.author_id == user.id || user.editor? || user.admin?
    end

    # Step 1: Load and validate article
    step :validate_article,
         with: Article::ValidateService,
         params: ->(context) {
           {
             id: context[:article_id]
           }
         }

    # Step 2: Check for plagiarism
    step :check_plagiarism,
         with: Article::PlagiarismCheckService,
         params: ->(context) {
           {
             article_id: context[:article].id
           }
         }

    # Step 3: Generate SEO metadata
    step :generate_seo,
         with: Article::GenerateSEOService,
         params: ->(context) {
           {
             article_id: context[:article].id
           }
         }

    # Step 4: Optimize and compress images
    step :optimize_images,
         with: Article::OptimizeImagesService,
         params: ->(context) {
           {
             article_id: context[:article].id
           }
         }

    # Step 5: Generate social media preview
    step :generate_preview,
         with: Article::GenerateSocialPreviewService,
         params: ->(context) {
           {
             article_id: context[:article].id
           }
         }

    # Step 6: Publish the article
    step :publish_article,
         with: Article::PublishService,
         params: ->(context) {
           {
             id: context[:article].id,
             publish_at: context[:publish_at],
             featured: context[:featured]
           }
         }

    # Step 7: Update search index
    step :index_search,
         with: Article::IndexSearchService,
         params: ->(context) {
           {
             article_id: context[:article].id
           }
         }

    # Step 8: Generate sitemap
    step :update_sitemap,
         with: Sitemap::UpdateService

    # Step 9: Notify subscribers
    step :notify_subscribers,
         with: Article::NotifySubscribersService,
         if: ->(context) {
           context[:notify_subscribers] != false &&
           context[:article].published_at <= Time.current
         },
         params: ->(context) {
           {
             article_id: context[:article].id
           }
         }

    # Step 10: Share on social media
    step :share_on_twitter,
         with: Article::ShareOnTwitterService,
         if: ->(context) { context[:share_on_social] == true },
         params: ->(context) {
           {
             article_id: context[:article].id
           }
         }

    step :share_on_linkedin,
         with: Article::ShareOnLinkedInService,
         if: ->(context) { context[:share_on_social] == true },
         params: ->(context) {
           {
             article_id: context[:article].id
           }
         }

    # Step 11: Track event
    step :track_publish,
         with: Analytics::TrackPublishService,
         params: ->(context) {
           {
             article_id: context[:article].id,
             author_id: user.id
           }
         }

    def after_execution(result)
      article = result[:article]
      scheduled = article.published_at > Time.current

      logger.info scheduled ?
        "Article scheduled for #{article.published_at}" :
        "Article published immediately"
    end
  end
end

# Usage
result = Article::PublishingWorkflow.new(current_user, params: {
  article_id: 123,
  publish_at: 2.hours.from_now,
  notify_subscribers: true,
  share_on_social: true,
  featured: true
}).call
```

---

## Payment Processing: Refund Workflow

### Order Refund Flow

```ruby
# app/workflows/payment/refund_workflow.rb
module Payment
  class RefundWorkflow < BetterService::Workflow
    schema do
      required(:order_id).filled(:integer)
      required(:reason).filled(:string, included_in?: %w[
        customer_request
        defective_product
        wrong_item
        not_as_described
        other
      ])

      optional(:refund_amount).maybe(:decimal)
      optional(:notes).maybe(:string)
      optional(:restock_items).maybe(:bool)
    end

    authorize_with do
      order = Order.find(params[:order_id])
      user.admin? || order.user_id == user.id
    end

    # Step 1: Validate refund eligibility
    step :validate_refund,
         with: Payment::ValidateRefundService,
         params: ->(context) {
           {
             order_id: context[:order_id],
             reason: context[:reason]
           }
         }

    # Step 2: Calculate refund amount
    step :calculate_refund,
         with: Payment::CalculateRefundService,
         params: ->(context) {
           {
             order_id: context[:order].id,
             requested_amount: context[:refund_amount]
           }
         }

    # Step 3: Process refund with payment gateway
    step :process_refund,
         with: Payment::ProcessRefundService,
         params: ->(context) {
           {
             payment_id: context[:order].payment_id,
             amount: context[:refund_amount_calculated],
             reason: context[:reason]
           }
         },
         on_error: ->(context, error) {
           PaymentLogger.log_refund_failure(context[:order], error)
         }

    # Step 4: Update order status
    step :update_order,
         with: Order::UpdateStatusService,
         params: ->(context) {
           {
             order_id: context[:order].id,
             status: 'refunded',
             refund_reason: context[:reason],
             refund_notes: context[:notes]
           }
         }

    # Step 5: Restock items
    step :restock_items,
         with: Inventory::RestockService,
         if: ->(context) { context[:restock_items] != false },
         params: ->(context) {
           {
             order_id: context[:order].id
           }
         }

    # Step 6: Send refund confirmation email
    step :send_confirmation,
         with: Email::RefundConfirmationService,
         params: ->(context) {
           {
             order_id: context[:order].id,
             refund_amount: context[:refund_amount_calculated]
           }
         }

    # Step 7: Notify customer service
    step :notify_cs,
         with: Slack::NotifyCustomerServiceService,
         params: ->(context) {
           {
             order_id: context[:order].id,
             reason: context[:reason],
             amount: context[:refund_amount_calculated]
           }
         }

    # Step 8: Track refund metric
    step :track_refund,
         with: Analytics::TrackRefundService,
         params: ->(context) {
           {
             order_id: context[:order].id,
             reason: context[:reason],
             amount: context[:refund_amount_calculated]
           }
         }

    def after_execution(result)
      Metrics.increment('refunds.processed', tags: {
        reason: result[:reason]
      })
    end
  end
end

# Usage
result = Payment::RefundWorkflow.new(current_user, params: {
  order_id: 789,
  reason: 'defective_product',
  notes: 'Product arrived damaged',
  restock_items: true
}).call
```

---

## Data Import: CSV Import Workflow

### Bulk CSV Import

```ruby
# app/workflows/import/csv_import_workflow.rb
module Import
  class CSVImportWorkflow < BetterService::Workflow
    schema do
      required(:file).filled(:hash)
      required(:model_type).filled(:string, included_in?: %w[products users orders])

      optional(:update_existing).maybe(:bool)
      optional(:skip_errors).maybe(:bool)
      optional(:notify_on_completion).maybe(:bool)
    end

    authorize_with do
      user.admin? || user.has_permission?(:import_data)
    end

    # Step 1: Validate file format
    step :validate_file,
         with: Import::ValidateFileService,
         params: ->(context) {
           {
             file: context[:file],
             model_type: context[:model_type]
           }
         }

    # Step 2: Parse CSV
    step :parse_csv,
         with: Import::ParseCSVService,
         params: ->(context) {
           {
             file: context[:file]
           }
         }

    # Step 3: Validate headers
    step :validate_headers,
         with: Import::ValidateHeadersService,
         params: ->(context) {
           {
             headers: context[:parsed_data].headers,
             model_type: context[:model_type]
           }
         }

    # Step 4: Create import record
    step :create_import_record,
         with: Import::CreateRecordService,
         params: ->(context) {
           {
             user_id: user.id,
             model_type: context[:model_type],
             total_rows: context[:parsed_data].rows.count,
             status: 'processing'
           }
         }

    # Step 5: Process rows
    step :process_rows,
         with: Import::ProcessRowsService,
         params: ->(context) {
           {
             import_id: context[:import_record].id,
             rows: context[:parsed_data].rows,
             model_type: context[:model_type],
             update_existing: context[:update_existing],
             skip_errors: context[:skip_errors]
           }
         }

    # Step 6: Generate report
    step :generate_report,
         with: Import::GenerateReportService,
         params: ->(context) {
           {
             import_id: context[:import_record].id,
             results: context[:import_results]
           }
         }

    # Step 7: Update import record
    step :finalize_import,
         with: Import::FinalizeService,
         params: ->(context) {
           {
             import_id: context[:import_record].id,
             status: 'completed',
             results: context[:import_results]
           }
         }

    # Step 8: Send notification
    step :send_notification,
         with: Email::ImportCompletionService,
         if: ->(context) { context[:notify_on_completion] != false },
         params: ->(context) {
           {
             user_id: user.id,
             import_id: context[:import_record].id,
             report: context[:report]
           }
         }

    # Step 9: Clear cache
    step :clear_cache,
         with: Cache::ClearModelCacheService,
         params: ->(context) {
           {
             model_type: context[:model_type]
           }
         }

    def after_execution(result)
      results = result[:import_results]
      logger.info "Import completed: #{results[:created]} created, " \
                  "#{results[:updated]} updated, #{results[:errors]} errors"
    end

    def on_workflow_error(error)
      # Mark import as failed
      if context[:import_record]
        Import::FinalizeService.new(user, params: {
          import_id: context[:import_record].id,
          status: 'failed',
          error_message: error.message
        }).call rescue nil
      end
    end
  end
end

# Usage
result = Import::CSVImportWorkflow.new(current_user, params: {
  file: uploaded_file,
  model_type: 'products',
  update_existing: true,
  skip_errors: true,
  notify_on_completion: true
}).call

flash[:notice] = "Import completed: #{result[:import_results][:created]} created"
```

---

## Conditional Branching: Payment Method Routing

### Payment Processing with Branching

```ruby
# app/workflows/order/process_payment_workflow.rb
module Order
  class ProcessPaymentWorkflow < BetterService::Workflow
    schema do
      required(:order_id).filled(:integer)
      required(:payment_method).filled(:string, included_in?: %w[
        credit_card paypal bank_transfer crypto
      ])
      optional(:save_payment).maybe(:bool)
    end

    authorize_with do
      order = Order.find(params[:order_id])
      order.user_id == user.id || user.admin?
    end

    # Step 1: Validate order
    step :validate_order,
         with: Order::ValidateService,
         params: ->(context) {
           {
             id: context[:order_id]
           }
         }

    # Step 2: Branch based on payment method
    branch do
      # Credit Card Path
      on ->(ctx) { ctx.payment_method == 'credit_card' } do
        step :validate_card,
             with: Payment::ValidateCardService,
             params: ->(ctx) {
               {
                 card_token: ctx[:card_token]
               }
             }

        step :charge_credit_card,
             with: Payment::ChargeCreditCardService,
             params: ->(ctx) {
               {
                 order_id: ctx.validate_order.id,
                 amount: ctx.validate_order.total,
                 card_token: ctx[:card_token]
               }
             },
             on_error: ->(ctx, error) {
               PaymentLogger.log_failure(ctx.validate_order, error)
             }

        step :verify_3d_secure,
             with: Payment::Verify3DSecureService,
             if: ->(ctx) { ctx.charge_credit_card.requires_3d_secure? },
             params: ->(ctx) {
               {
                 charge_id: ctx.charge_credit_card.id
               }
             }

        step :store_card,
             with: Payment::StoreCardService,
             if: ->(ctx) { ctx[:save_payment] == true },
             params: ->(ctx) {
               {
                 user_id: user.id,
                 card_token: ctx[:card_token]
               }
             }
      end

      # PayPal Path
      on ->(ctx) { ctx.payment_method == 'paypal' } do
        step :create_paypal_order,
             with: Payment::Paypal::CreateOrderService,
             params: ->(ctx) {
               {
                 order_id: ctx.validate_order.id,
                 amount: ctx.validate_order.total,
                 return_url: ctx[:return_url],
                 cancel_url: ctx[:cancel_url]
               }
             }

        step :capture_paypal_payment,
             with: Payment::Paypal::CaptureService,
             params: ->(ctx) {
               {
                 paypal_order_id: ctx.create_paypal_order.id
               }
             }
      end

      # Bank Transfer Path
      on ->(ctx) { ctx.payment_method == 'bank_transfer' } do
        step :generate_transfer_reference,
             with: Payment::BankTransfer::GenerateReferenceService,
             params: ->(ctx) {
               {
                 order_id: ctx.validate_order.id
               }
             }

        step :send_transfer_instructions,
             with: Email::BankInstructionsService,
             params: ->(ctx) {
               {
                 order_id: ctx.validate_order.id,
                 reference: ctx.generate_transfer_reference.reference,
                 amount: ctx.validate_order.total
               }
             }

        step :mark_pending,
             with: Order::MarkPendingService,
             params: ->(ctx) {
               {
                 order_id: ctx.validate_order.id
               }
             }
      end

      # Cryptocurrency Path
      on ->(ctx) { ctx.payment_method == 'crypto' } do
        step :create_crypto_invoice,
             with: Payment::Crypto::CreateInvoiceService,
             params: ->(ctx) {
               {
                 order_id: ctx.validate_order.id,
                 amount: ctx.validate_order.total,
                 currency: ctx[:crypto_currency] || 'BTC'
               }
             }

        step :monitor_payment,
             with: Payment::Crypto::MonitorPaymentService,
             params: ->(ctx) {
               {
                 invoice_id: ctx.create_crypto_invoice.id
               }
             }
      end

      # Default: Unsupported Method
      otherwise do
        step :log_unsupported_method,
             with: Logging::LogUnsupportedPaymentService,
             params: ->(ctx) {
               {
                 order_id: ctx.validate_order.id,
                 payment_method: ctx.payment_method
               }
             }

        step :notify_admin,
             with: Email::AdminNotificationService,
             params: ->(ctx) {
               {
                 subject: "Unsupported payment method attempted",
                 details: {
                   order_id: ctx.validate_order.id,
                   payment_method: ctx.payment_method
                 }
               }
             }
      end
    end

    # Step 3: Update order status (after payment)
    step :update_order_status,
         with: Order::UpdateStatusService,
         unless: ->(ctx) { ctx.payment_method == 'bank_transfer' },
         params: ->(ctx) {
           {
             order_id: ctx.validate_order.id,
             status: 'processing'
           }
         }

    # Step 4: Send confirmation
    step :send_confirmation,
         with: Email::PaymentConfirmationService,
         params: ->(ctx) {
           {
             order_id: ctx.validate_order.id,
             payment_method: ctx.payment_method
           }
         }

    def after_execution(result)
      Metrics.increment('payment.processed', tags: {
        method: result[:payment_method]
      })
    end
  end
end

# Usage
result = Order::ProcessPaymentWorkflow.new(current_user, params: {
  order_id: 123,
  payment_method: 'credit_card',
  card_token: 'tok_visa_4242',
  save_payment: true
}).call
```

---

## Conditional Branching: Document Approval

### Nested Approval Based on Document Type and Value

```ruby
# app/workflows/document/approval_workflow.rb
module Document
  class ApprovalWorkflow < BetterService::Workflow
    schema do
      required(:document_id).filled(:integer)
      optional(:expedite).maybe(:bool)
      optional(:notes).maybe(:string)
    end

    authorize_with do
      document = Document.find(params[:document_id])
      document.submitter_id == user.id || user.approver? || user.admin?
    end

    # Step 1: Validate document
    step :validate_document,
         with: Document::ValidateService,
         params: ->(context) {
           {
             id: context[:document_id]
           }
         }

    # Step 2: Check completeness
    step :check_completeness,
         with: Document::CheckCompletenessService,
         params: ->(context) {
           {
             document_id: context.validate_document.id
           }
         }

    # Step 3: Branch by document type
    branch do
      # Contract Documents
      on ->(ctx) { ctx.validate_document.type == 'contract' } do
        step :legal_review,
             with: Legal::ReviewService,
             params: ->(ctx) {
               {
                 document_id: ctx.validate_document.id
               }
             }

        # Nested branch by contract value
        branch do
          on ->(ctx) { ctx.validate_document.value > 100_000 } do
            step :ceo_approval,
                 with: Approval::CEOService,
                 params: ->(ctx) {
                   {
                     document_id: ctx.validate_document.id,
                     legal_review: ctx.legal_review
                   }
                 }

            step :board_approval,
                 with: Approval::BoardService,
                 params: ->(ctx) {
                   {
                     document_id: ctx.validate_document.id,
                     ceo_approval: ctx.ceo_approval
                   }
                 }
          end

          on ->(ctx) { ctx.validate_document.value > 10_000 } do
            step :manager_approval,
                 with: Approval::ManagerService,
                 params: ->(ctx) {
                   {
                     document_id: ctx.validate_document.id,
                     legal_review: ctx.legal_review
                   }
                 }
          end

          otherwise do
            step :supervisor_approval,
                 with: Approval::SupervisorService,
                 params: ->(ctx) {
                   {
                     document_id: ctx.validate_document.id
                   }
                 }
          end
        end
      end

      # Invoice Documents
      on ->(ctx) { ctx.validate_document.type == 'invoice' } do
        branch do
          on ->(ctx) { ctx.validate_document.amount > 5_000 } do
            step :finance_manager_approval,
                 with: Approval::FinanceManagerService,
                 params: ->(ctx) {
                   {
                     document_id: ctx.validate_document.id
                   }
                 }
          end

          on ->(ctx) { ctx.validate_document.amount > 1_000 } do
            step :accountant_approval,
                 with: Approval::AccountantService,
                 params: ->(ctx) {
                   {
                     document_id: ctx.validate_document.id
                   }
                 }
          end

          otherwise do
            step :auto_approve_invoice,
                 with: Approval::AutoApproveService,
                 params: ->(ctx) {
                   {
                     document_id: ctx.validate_document.id
                   }
                 }
          end
        end
      end

      # Purchase Order Documents
      on ->(ctx) { ctx.validate_document.type == 'purchase_order' } do
        step :procurement_review,
             with: Procurement::ReviewService,
             params: ->(ctx) {
               {
                 document_id: ctx.validate_document.id
               }
             }

        step :budget_check,
             with: Finance::BudgetCheckService,
             params: ->(ctx) {
               {
                 document_id: ctx.validate_document.id,
                 procurement_review: ctx.procurement_review
               }
             }

        step :director_approval,
             with: Approval::DirectorService,
             params: ->(ctx) {
               {
                 document_id: ctx.validate_document.id
               }
             }
      end

      # Standard Documents (policies, memos, etc.)
      otherwise do
        step :standard_approval,
             with: Approval::StandardService,
             params: ->(ctx) {
               {
                 document_id: ctx.validate_document.id
               }
             }
      end
    end

    # Step 4: Finalize document
    step :finalize_document,
         with: Document::FinalizeService,
         params: ->(context) {
           {
             document_id: context.validate_document.id,
             status: 'approved'
           }
         }

    # Step 5: Notify stakeholders
    step :notify_stakeholders,
         with: Email::ApprovalNotificationService,
         params: ->(context) {
           {
             document_id: context.validate_document.id
           }
         }

    def after_execution(result)
      document = result[:validate_document]
      logger.info "Document #{document.id} (#{document.type}) approved " \
                  "via branch: #{result[:metadata][:branches_taken].join(' -> ')}"
    end
  end
end

# Usage
result = Document::ApprovalWorkflow.new(current_user, params: {
  document_id: 456,
  notes: "Urgent approval needed"
}).call

# Metadata shows which approval path was taken
result[:metadata][:branches_taken]
# => ["branch_1:on_1", "nested_branch_1:on_1"]  # Contract > $100k path
```

---

## Conditional Branching: User Tier Features

### Subscription Feature Access Based on Tier

```ruby
# app/workflows/subscription/feature_access_workflow.rb
module Subscription
  class FeatureAccessWorkflow < BetterService::Workflow
    schema do
      required(:user_id).filled(:integer)
      required(:feature_name).filled(:string)
      optional(:metadata).maybe(:hash)
    end

    authorize_with do
      user.active? && !user.suspended?
    end

    # Step 1: Load user subscription
    step :load_subscription,
         with: Subscription::LoadService,
         params: ->(context) {
           {
             user_id: context[:user_id]
           }
         }

    # Step 2: Check feature limits
    step :check_limits,
         with: Usage::CheckLimitsService,
         params: ->(context) {
           {
             user_id: context[:user_id],
             feature: context[:feature_name]
           }
         }

    # Step 3: Branch by subscription tier
    branch do
      # Enterprise Tier
      on ->(ctx) { ctx.load_subscription.tier == 'enterprise' } do
        step :enable_enterprise_features,
             with: Features::EnableEnterpriseService,
             params: ->(ctx) {
               {
                 user_id: ctx[:user_id],
                 feature: ctx[:feature_name]
               }
             }

        step :assign_account_manager,
             with: Support::AssignAccountManagerService,
             if: ->(ctx) { !ctx.load_subscription.has_account_manager? },
             params: ->(ctx) {
               {
                 user_id: ctx[:user_id]
               }
             }

        step :enable_custom_integrations,
             with: Features::EnableIntegrationsService,
             params: ->(ctx) {
               {
                 user_id: ctx[:user_id]
               }
             }

        step :configure_sso,
             with: Auth::ConfigureSSOService,
             if: ->(ctx) { ctx.load_subscription.sso_enabled? },
             params: ->(ctx) {
               {
                 user_id: ctx[:user_id]
               }
             }
      end

      # Premium Tier
      on ->(ctx) { ctx.load_subscription.tier == 'premium' } do
        step :enable_premium_features,
             with: Features::EnablePremiumService,
             params: ->(ctx) {
               {
                 user_id: ctx[:user_id],
                 feature: ctx[:feature_name]
               }
             }

        step :enable_priority_support,
             with: Support::EnablePrioritySupportService,
             params: ->(ctx) {
               {
                 user_id: ctx[:user_id]
               }
             }

        step :enable_advanced_analytics,
             with: Analytics::EnableAdvancedService,
             params: ->(ctx) {
               {
                 user_id: ctx[:user_id]
               }
             }
      end

      # Pro Tier
      on ->(ctx) { ctx.load_subscription.tier == 'pro' } do
        step :enable_pro_features,
             with: Features::EnableProService,
             params: ->(ctx) {
               {
                 user_id: ctx[:user_id],
                 feature: ctx[:feature_name]
               }
             }

        step :enable_standard_support,
             with: Support::EnableStandardService,
             params: ->(ctx) {
               {
                 user_id: ctx[:user_id]
               }
             }
      end

      # Free Tier
      on ->(ctx) { ctx.load_subscription.tier == 'free' } do
        step :enable_basic_features,
             with: Features::EnableBasicService,
             params: ->(ctx) {
               {
                 user_id: ctx[:user_id],
                 feature: ctx[:feature_name]
               }
             }

        step :show_upgrade_prompt,
             with: UI::ShowUpgradePromptService,
             if: ->(ctx) { ctx[:feature_name] in %w[advanced export api] },
             params: ->(ctx) {
               {
                 user_id: ctx[:user_id],
                 desired_feature: ctx[:feature_name]
               }
             }
      end

      # Trial or Unknown
      otherwise do
        step :enable_trial_features,
             with: Features::EnableTrialService,
             params: ->(ctx) {
               {
                 user_id: ctx[:user_id],
                 feature: ctx[:feature_name]
               }
             }
      end
    end

    # Step 4: Log access
    step :log_feature_access,
         with: Usage::LogAccessService,
         params: ->(context) {
           {
             user_id: context[:user_id],
             feature: context[:feature_name],
             tier: context.load_subscription.tier
           }
         }

    # Step 5: Track usage metrics
    step :track_usage,
         with: Analytics::TrackUsageService,
         params: ->(context) {
           {
             user_id: context[:user_id],
             event: "feature_accessed",
             properties: {
               feature: context[:feature_name],
               tier: context.load_subscription.tier
             }
           }
         }

    def after_execution(result)
      Metrics.increment('feature.access', tags: {
        tier: result[:load_subscription].tier,
        feature: result[:feature_name]
      })
    end
  end
end

# Usage
result = Subscription::FeatureAccessWorkflow.new(current_user, params: {
  user_id: current_user.id,
  feature_name: 'advanced_export'
}).call
```

---

## Conditional Branching: Content Processing

### Content Type Processing Pipeline

```ruby
# app/workflows/content/processing_workflow.rb
module Content
  class ProcessingWorkflow < BetterService::Workflow
    schema do
      required(:content_id).filled(:integer)
      optional(:priority).maybe(:string, included_in?: %w[low normal high urgent])
      optional(:auto_publish).maybe(:bool)
    end

    authorize_with do
      content = Content.find(params[:content_id])
      content.author_id == user.id || user.editor? || user.admin?
    end

    # Step 1: Load and validate content
    step :load_content,
         with: Content::LoadService,
         params: ->(context) {
           {
             id: context[:content_id]
           }
         }

    # Step 2: Virus scan
    step :virus_scan,
         with: Security::VirusScanService,
         params: ->(context) {
           {
             content_id: context.load_content.id
           }
         }

    # Step 3: Branch by content type
    branch do
      # Video Content
      on ->(ctx) { ctx.load_content.type == 'video' } do
        step :extract_metadata,
             with: Video::ExtractMetadataService,
             params: ->(ctx) {
               {
                 content_id: ctx.load_content.id
               }
             }

        step :generate_thumbnails,
             with: Video::GenerateThumbnailsService,
             params: ->(ctx) {
               {
                 content_id: ctx.load_content.id,
                 timestamps: [0, 5, 10, 30]
               }
             }

        step :transcode_video,
             with: Video::TranscodeService,
             params: ->(ctx) {
               {
                 content_id: ctx.load_content.id,
                 formats: ['720p', '1080p', '4k'],
                 codec: 'h264'
               }
             }

        step :generate_subtitles,
             with: Video::GenerateSubtitlesService,
             if: ->(ctx) { ctx[:priority] in %w[high urgent] },
             params: ->(ctx) {
               {
                 content_id: ctx.load_content.id
               }
             }
      end

      # Image Content
      on ->(ctx) { ctx.load_content.type == 'image' } do
        step :extract_exif,
             with: Image::ExtractExifService,
             params: ->(ctx) {
               {
                 content_id: ctx.load_content.id
               }
             }

        step :optimize_image,
             with: Image::OptimizeService,
             params: ->(ctx) {
               {
                 content_id: ctx.load_content.id,
                 quality: 85
               }
             }

        step :generate_variants,
             with: Image::GenerateVariantsService,
             params: ->(ctx) {
               {
                 content_id: ctx.load_content.id,
                 sizes: ['thumb', 'medium', 'large', 'xlarge']
               }
             }

        step :detect_faces,
             with: Image::DetectFacesService,
             if: ->(ctx) { ctx.load_content.enable_face_detection? },
             params: ->(ctx) {
               {
                 content_id: ctx.load_content.id
               }
             }
      end

      # Audio Content
      on ->(ctx) { ctx.load_content.type == 'audio' } do
        step :extract_audio_metadata,
             with: Audio::ExtractMetadataService,
             params: ->(ctx) {
               {
                 content_id: ctx.load_content.id
               }
             }

        step :normalize_audio,
             with: Audio::NormalizeService,
             params: ->(ctx) {
               {
                 content_id: ctx.load_content.id,
                 target_db: -14
               }
             }

        step :transcode_audio,
             with: Audio::TranscodeService,
             params: ->(ctx) {
               {
                 content_id: ctx.load_content.id,
                 formats: ['mp3', 'aac', 'ogg']
               }
             }

        step :generate_waveform,
             with: Audio::GenerateWaveformService,
             params: ->(ctx) {
               {
                 content_id: ctx.load_content.id
               }
             }
      end

      # Document Content (PDF, DOC, etc.)
      on ->(ctx) { ctx.load_content.type == 'document' } do
        step :extract_text,
             with: Document::ExtractTextService,
             params: ->(ctx) {
               {
                 content_id: ctx.load_content.id
               }
             }

        step :generate_preview_images,
             with: Document::GeneratePreviewService,
             params: ->(ctx) {
               {
                 content_id: ctx.load_content.id,
                 max_pages: 10
               }
             }

        step :index_for_search,
             with: Search::IndexDocumentService,
             params: ->(ctx) {
               {
                 content_id: ctx.load_content.id,
                 text: ctx.extract_text.full_text
               }
             }
      end

      # Unknown or Unsupported Type
      otherwise do
        step :generic_processing,
             with: Content::GenericProcessingService,
             params: ->(ctx) {
               {
                 content_id: ctx.load_content.id
               }
             }

        step :notify_admin_unknown_type,
             with: Email::AdminNotificationService,
             params: ->(ctx) {
               {
                 subject: "Unknown content type processed",
                 details: {
                   content_id: ctx.load_content.id,
                   type: ctx.load_content.type
                 }
               }
             }
      end
    end

    # Step 4: Generate CDN URLs
    step :generate_cdn_urls,
         with: CDN::GenerateUrlsService,
         params: ->(context) {
           {
             content_id: context.load_content.id
           }
         }

    # Step 5: Update status
    step :update_status,
         with: Content::UpdateStatusService,
         params: ->(context) {
           {
             content_id: context.load_content.id,
             status: 'processed'
           }
         }

    # Step 6: Auto-publish if requested
    step :publish_content,
         with: Content::PublishService,
         if: ->(ctx) { ctx[:auto_publish] == true },
         params: ->(context) {
           {
             content_id: context.load_content.id
           }
         }

    # Step 7: Notify author
    step :notify_author,
         with: Email::ProcessingCompleteService,
         params: ->(context) {
           {
             content_id: context.load_content.id,
             author_id: context.load_content.author_id
           }
         }

    def after_execution(result)
      content = result[:load_content]
      branch_path = result[:metadata][:branches_taken].first

      logger.info "Content #{content.id} (#{content.type}) processed via #{branch_path}"

      Metrics.timing('content.processing_time',
                     result[:metadata][:duration_ms],
                     tags: { type: content.type })
    end
  end
end

# Usage
result = Content::ProcessingWorkflow.new(current_user, params: {
  content_id: 789,
  priority: 'high',
  auto_publish: false
}).call

# Branch taken
result[:metadata][:branches_taken]
# => ["branch_1:on_1"]  # Video processing path
```

---

## Best Practices Demonstrated

### 1. Clear Step Names
All examples use descriptive step names that explain what happens.

### 2. Proper Parameter Mapping
Steps map only the parameters they need from context.

### 3. Conditional Logic
Steps use `if` conditions for optional operations.

### 4. Error Handling
Critical steps have `on_error` callbacks for logging.

### 5. Lifecycle Hooks
Workflows use `after_execution` and `on_workflow_error` appropriately.

### 6. Authorization
All workflows check user permissions.

### 7. Validation
All workflows validate input parameters.

### 8. Transaction Safety
All workflows rely on automatic transaction management.

### 9. Observable
Workflows log important events and track metrics.

### 10. Testable
Workflows are structured to be easily tested.

---

**See also:**
- [Workflows Introduction](01_workflows_introduction.md)
- [Workflow Steps](02_workflow_steps.md)
- [Workflow Context](03_workflow_context.md)
- [Workflow Lifecycle](04_workflow_lifecycle.md)
- [Workflow Generator](../generators/03_workflow_generator.md)
