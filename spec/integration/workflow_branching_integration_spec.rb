# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workflow Branching Integration", type: :integration do
  let(:user) { User.create!(name: "Test User", email: "test@example.com") }

  after do
    Product.destroy_all
    Booking.destroy_all
    User.destroy_all
  end

  # Test Services for Product Publishing Workflow
  class ValidateProductService < BetterService::Services::Base
    schema { required(:product_id).filled(:integer) }

    process_with do |_data|
      product = Product.find(params[:product_id])
      { resource: product }
    end
  end

  class PublishProductService < BetterService::Services::Base
    schema { required(:product).filled }

    process_with do |_data|
      product = params[:product]
      product.update!(published: true)
      { resource: product }
    end
  end

  class SendPublishNotificationService < BetterService::Services::Base
    schema { required(:product).filled }

    process_with do |_data|
      { resource: { sent: true, product_name: params[:product].name } }
    end
  end

  class SchedulePromotionService < BetterService::Services::Base
    schema { required(:product).filled }

    process_with do |_data|
      { resource: { scheduled: true, promotion_date: 7.days.from_now } }
    end
  end

  class SendDraftReminderService < BetterService::Services::Base
    schema { required(:product).filled }

    process_with do |_data|
      { resource: { reminder_sent: true } }
    end
  end

  class ProductPublishingWorkflow < BetterService::Workflows::Base
    with_transaction true

    step :validate_product,
         with: ValidateProductService,
         input: ->(ctx) { { product_id: ctx.product_id } }

    branch do
      on ->(ctx) { ctx.validate_product.published } do
        step :send_notification,
             with: SendPublishNotificationService,
             input: ->(ctx) { { product: ctx.validate_product } }

        branch do
          on ->(ctx) { ctx.validate_product.price > 100 } do
            step :schedule_promotion,
                 with: SchedulePromotionService,
                 input: ->(ctx) { { product: ctx.validate_product } }
          end

          otherwise do
            # No promotion for cheaper products
          end
        end
      end

      otherwise do
        step :send_draft_reminder,
             with: SendDraftReminderService,
             input: ->(ctx) { { product: ctx.validate_product } }
      end
    end
  end

  describe "Product Publishing Workflow" do
    it "sends notification and schedules promotion for published expensive product" do
      product = Product.create!(
        name: "Premium Widget",
        price: 199.99,
        published: true,
        user: user
      )

      workflow = ProductPublishingWorkflow.new(user, params: { product_id: product.id })
      result = workflow.call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to eq [:validate_product, :send_notification, :schedule_promotion]
      expect(result[:metadata][:branches_taken].count).to eq 2
      expect(result[:metadata][:branches_taken]).to include "branch_1:on_1"
      expect(result[:context].send_notification[:sent]).to be true
      expect(result[:context].schedule_promotion[:scheduled]).to be true
    end

    it "sends notification only for published cheap product" do
      product = Product.create!(
        name: "Budget Widget",
        price: 9.99,
        published: true,
        user: user
      )

      workflow = ProductPublishingWorkflow.new(user, params: { product_id: product.id })
      result = workflow.call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to eq [:validate_product, :send_notification]
      expect(result[:metadata][:branches_taken].count).to eq 2
      expect(result[:context].send_notification[:sent]).to be true
      expect(result[:context]).not_to respond_to(:schedule_promotion)
    end

    it "sends draft reminder for unpublished product" do
      product = Product.create!(
        name: "Draft Widget",
        price: 49.99,
        published: false,
        user: user
      )

      workflow = ProductPublishingWorkflow.new(user, params: { product_id: product.id })
      result = workflow.call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to eq [:validate_product, :send_draft_reminder]
      expect(result[:metadata][:branches_taken]).to include "branch_1:otherwise"
      expect(result[:context].send_draft_reminder[:reminder_sent]).to be true
    end
  end

  # Test Services for Booking Approval Workflow
  class FetchBookingService < BetterService::Services::Base
    schema { required(:booking_id).filled(:integer) }

    process_with do |_data|
      booking = Booking.find(params[:booking_id])
      { resource: booking }
    end
  end

  class AutoApproveBookingService < BetterService::Services::Base
    schema { required(:booking).filled }

    process_with do |_data|
      booking = params[:booking]
      { resource: { booking_id: booking.id, status: "auto_approved", approved_at: Time.current } }
    end
  end

  class RequestManagerApprovalService < BetterService::Services::Base
    schema { required(:booking).filled }

    process_with do |_data|
      booking = params[:booking]
      { resource: { booking_id: booking.id, status: "pending_manager", requested_at: Time.current } }
    end
  end

  class RequestExecutiveApprovalService < BetterService::Services::Base
    schema { required(:booking).filled }

    process_with do |_data|
      booking = params[:booking]
      { resource: { booking_id: booking.id, status: "pending_executive", requested_at: Time.current } }
    end
  end

  class SendApprovalNotificationService < BetterService::Services::Base
    schema { optional(:context).filled }

    process_with do |_data|
      { resource: { notification_sent: true } }
    end
  end

  class BookingApprovalWorkflow < BetterService::Workflows::Base
    step :fetch_booking,
         with: FetchBookingService,
         input: ->(ctx) { { booking_id: ctx.booking_id } }

    branch do
      on ->(ctx) { ctx.fetch_booking.date <= 30.days.from_now.to_date } do
        step :auto_approve,
             with: AutoApproveBookingService,
             input: ->(ctx) { { booking: ctx.fetch_booking } }
      end

      on ->(ctx) {
        ctx.fetch_booking.date > 30.days.from_now.to_date &&
        ctx.fetch_booking.date <= 90.days.from_now.to_date
      } do
        step :request_manager_approval,
             with: RequestManagerApprovalService,
             input: ->(ctx) { { booking: ctx.fetch_booking } }
      end

      otherwise do
        step :request_executive_approval,
             with: RequestExecutiveApprovalService,
             input: ->(ctx) { { booking: ctx.fetch_booking } }
      end
    end

    step :send_notification,
         with: SendApprovalNotificationService
  end

  describe "Booking Approval Workflow" do
    it "auto-approves recent booking" do
      booking = Booking.create!(
        title: "Team Meeting",
        description: "Weekly team sync",
        date: 15.days.from_now.to_date,
        user: user
      )

      workflow = BookingApprovalWorkflow.new(user, params: { booking_id: booking.id })
      result = workflow.call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to eq [:fetch_booking, :auto_approve, :send_notification]
      expect(result[:metadata][:branches_taken]).to include "branch_1:on_1"
      expect(result[:context].auto_approve[:status]).to eq "auto_approved"
    end

    it "requires manager approval for medium-future booking" do
      booking = Booking.create!(
        title: "Conference Room",
        description: "Quarterly planning",
        date: 60.days.from_now.to_date,
        user: user
      )

      workflow = BookingApprovalWorkflow.new(user, params: { booking_id: booking.id })
      result = workflow.call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to eq [:fetch_booking, :request_manager_approval, :send_notification]
      expect(result[:metadata][:branches_taken]).to include "branch_1:on_2"
      expect(result[:context].request_manager_approval[:status]).to eq "pending_manager"
    end

    it "requires executive approval for far-future booking" do
      booking = Booking.create!(
        title: "Annual Conference",
        description: "Company-wide event",
        date: 120.days.from_now.to_date,
        user: user
      )

      workflow = BookingApprovalWorkflow.new(user, params: { booking_id: booking.id })
      result = workflow.call

      expect(result[:success]).to be true
      expect(result[:metadata][:steps_executed]).to eq [:fetch_booking, :request_executive_approval, :send_notification]
      expect(result[:metadata][:branches_taken]).to include "branch_1:otherwise"
      expect(result[:context].request_executive_approval[:status]).to eq "pending_executive"
    end
  end

  # Test Services for Transaction Rollback
  class CreateProductService < BetterService::Services::Base
    schema do
      required(:name).filled(:string)
      required(:price).filled(:decimal)
    end

    process_with do |_data|
      product = Product.create!(
        name: params[:name],
        price: params[:price],
        user: user
      )
      { resource: product }
    end
  end

  class FailingPublishService < BetterService::Services::Base
    schema { required(:product).filled }

    process_with do |_data|
      raise StandardError, "Publishing failed"
    end
  end

  class ProductCreationWorkflow < BetterService::Workflows::Base
    with_transaction true

    step :create_product,
         with: CreateProductService,
         input: ->(ctx) { { name: ctx.product_name, price: ctx.product_price } }

    branch do
      on ->(ctx) { ctx.should_publish } do
        step :publish_product,
             with: FailingPublishService,
             input: ->(ctx) { { product: ctx.create_product } }
      end

      otherwise do
        # Leave as draft
      end
    end
  end

  describe "Transaction Rollback in Branches" do
    it "rolls back all database changes on branch failure" do
      initial_count = Product.count

      expect {
        workflow = ProductCreationWorkflow.new(
          user,
          params: { product_name: "Test Product", product_price: 99.99, should_publish: true }
        )
        workflow.call
      }.to raise_error(BetterService::Errors::Workflowable::Runtime::StepExecutionError, /publish_product failed/)

      expect(Product.count).to eq initial_count
    end

    it "commits all changes on successful branch path" do
      initial_count = Product.count

      workflow = ProductCreationWorkflow.new(
        user,
        params: { product_name: "Draft Product", product_price: 49.99, should_publish: false }
      )
      result = workflow.call

      expect(result[:success]).to be true
      expect(Product.count).to eq initial_count + 1
      expect(Product.exists?(name: "Draft Product")).to be true
    end
  end

  describe "Multi-User Workflow with Branching" do
    it "executes user-specific branches correctly" do
      admin_user = User.create!(name: "Admin", email: "admin@example.com")
      regular_user = User.create!(name: "Regular", email: "regular@example.com")

      validate_service = Class.new(BetterService::Services::Base) do
        schema { optional(:context).filled }
        process_with { { resource: { validated: true } } }
      end

      admin_action_service = Class.new(BetterService::Services::Base) do
        schema { optional(:context).filled }
        process_with { { resource: { admin_action: true } } }
      end

      user_action_service = Class.new(BetterService::Services::Base) do
        schema { optional(:context).filled }
        process_with { { resource: { user_action: true } } }
      end

      workflow_class = Class.new(BetterService::Workflows::Base) do
        step :validate, with: validate_service

        branch do
          on ->(ctx) { ctx.user.name == "Admin" } do
            step :admin_action, with: admin_action_service
          end

          otherwise do
            step :user_action, with: user_action_service
          end
        end
      end

      admin_result = workflow_class.new(admin_user, params: {}).call
      expect(admin_result[:success]).to be true
      expect(admin_result[:metadata][:steps_executed]).to eq [:validate, :admin_action]
      expect(admin_result[:context].admin_action[:admin_action]).to be true

      user_result = workflow_class.new(regular_user, params: {}).call
      expect(user_result[:success]).to be true
      expect(user_result[:metadata][:steps_executed]).to eq [:validate, :user_action]
      expect(user_result[:context].user_action[:user_action]).to be true
    end
  end

  describe "Branching with Database Queries" do
    it "can use database queries in branch conditions" do
      expensive = Product.create!(name: "Expensive", price: 500, user: user)
      cheap = Product.create!(name: "Cheap", price: 10, user: user)

      fetch_product_service = Class.new(BetterService::Services::Base) do
        schema { required(:product_id).filled(:integer) }
        process_with do
          product = Product.find(params[:product_id])
          { resource: product }
        end
      end

      premium_service = Class.new(BetterService::Services::Base) do
        schema { optional(:context).filled }
        process_with { { resource: { tier: "premium" } } }
      end

      standard_service = Class.new(BetterService::Services::Base) do
        schema { optional(:context).filled }
        process_with { { resource: { tier: "standard" } } }
      end

      workflow_class = Class.new(BetterService::Workflows::Base) do
        step :fetch_product, with: fetch_product_service, input: ->(ctx) { { product_id: ctx.product_id } }

        branch do
          on ->(ctx) {
            Product.where("price > ?", 100).exists?(id: ctx.fetch_product.id)
          } do
            step :premium_handling, with: premium_service
          end

          otherwise do
            step :standard_handling, with: standard_service
          end
        end
      end

      expensive_result = workflow_class.new(user, params: { product_id: expensive.id }).call
      expect(expensive_result[:success]).to be true
      expect(expensive_result[:context].premium_handling[:tier]).to eq "premium"

      cheap_result = workflow_class.new(user, params: { product_id: cheap.id }).call
      expect(cheap_result[:success]).to be true
      expect(cheap_result[:context].standard_handling[:tier]).to eq "standard"
    end
  end
end
