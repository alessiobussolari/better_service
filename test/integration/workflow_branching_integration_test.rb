# frozen_string_literal: true

require "test_helper"

class WorkflowBranchingIntegrationTest < ActiveSupport::TestCase
  # Integration tests for workflow branching with real database models
  # These tests verify that branching works correctly with actual ActiveRecord models,
  # database transactions, and Rails features.

  setup do
    @user = User.create!(name: "Test User", email: "test@example.com")
  end

  teardown do
    Product.destroy_all
    Booking.destroy_all
    User.destroy_all
  end

  # ============================================================================
  # Test Scenario 1: Product Publishing Workflow with Status-based Branching
  # ============================================================================

  class ValidateProductService < BetterService::Services::Base
    schema do
      required(:product_id).filled(:integer)
    end

    process_with do |data|
      product = Product.find(params[:product_id])
      { resource: product }
    end
  end

  class PublishProductService < BetterService::Services::Base
    schema do
      required(:product).filled
    end

    process_with do |data|
      product = params[:product]
      product.update!(published: true)
      { resource: product }
    end
  end

  class SendPublishNotificationService < BetterService::Services::Base
    schema do
      required(:product).filled
    end

    process_with do |data|
      # Simulate sending notification
      { resource: { sent: true, product_name: params[:product].name } }
    end
  end

  class SchedulePromotionService < BetterService::Services::Base
    schema do
      required(:product).filled
    end

    process_with do |data|
      # Simulate scheduling promotion
      { resource: { scheduled: true, promotion_date: 7.days.from_now } }
    end
  end

  class SendDraftReminderService < BetterService::Services::Base
    schema do
      required(:product).filled
    end

    process_with do |data|
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

        # Nested branch for expensive products
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

  test "product workflow - published expensive product gets notification and promotion" do
    product = Product.create!(
      name: "Premium Widget",
      price: 199.99,
      published: true,
      user: @user
    )

    workflow = ProductPublishingWorkflow.new(@user, params: { product_id: product.id })
    result = workflow.call

    assert result[:success]
    assert_equal [:validate_product, :send_notification, :schedule_promotion], result[:metadata][:steps_executed]
    assert_equal 2, result[:metadata][:branches_taken].count
    assert_includes result[:metadata][:branches_taken], "branch_1:on_1"
    assert result[:context].send_notification[:sent]
    assert result[:context].schedule_promotion[:scheduled]
  end

  test "product workflow - published cheap product gets notification only" do
    product = Product.create!(
      name: "Budget Widget",
      price: 9.99,
      published: true,
      user: @user
    )

    workflow = ProductPublishingWorkflow.new(@user, params: { product_id: product.id })
    result = workflow.call

    assert result[:success]
    assert_equal [:validate_product, :send_notification], result[:metadata][:steps_executed]
    assert_equal 2, result[:metadata][:branches_taken].count
    assert result[:context].send_notification[:sent]
    refute result[:context].respond_to?(:schedule_promotion)
  end

  test "product workflow - draft product gets reminder" do
    product = Product.create!(
      name: "Draft Widget",
      price: 49.99,
      published: false,
      user: @user
    )

    workflow = ProductPublishingWorkflow.new(@user, params: { product_id: product.id })
    result = workflow.call

    assert result[:success]
    assert_equal [:validate_product, :send_draft_reminder], result[:metadata][:steps_executed]
    assert_includes result[:metadata][:branches_taken], "branch_1:otherwise"
    assert result[:context].send_draft_reminder[:reminder_sent]
  end

  # ============================================================================
  # Test Scenario 2: Booking Approval Workflow with Date-based Branching
  # ============================================================================

  class FetchBookingService < BetterService::Services::Base
    schema do
      required(:booking_id).filled(:integer)
    end

    process_with do |data|
      booking = Booking.find(params[:booking_id])
      { resource: booking }
    end
  end

  class AutoApproveBookingService < BetterService::Services::Base
    schema do
      required(:booking).filled
    end

    process_with do |data|
      booking = params[:booking]
      # Simulate auto-approval
      { resource: { booking_id: booking.id, status: "auto_approved", approved_at: Time.current } }
    end
  end

  class RequestManagerApprovalService < BetterService::Services::Base
    schema do
      required(:booking).filled
    end

    process_with do |data|
      booking = params[:booking]
      { resource: { booking_id: booking.id, status: "pending_manager", requested_at: Time.current } }
    end
  end

  class RequestExecutiveApprovalService < BetterService::Services::Base
    schema do
      required(:booking).filled
    end

    process_with do |data|
      booking = params[:booking]
      { resource: { booking_id: booking.id, status: "pending_executive", requested_at: Time.current } }
    end
  end

  class SendApprovalNotificationService < BetterService::Services::Base
    schema do
      optional(:context).filled
    end

    process_with do |data|
      { resource: { notification_sent: true } }
    end
  end

  class BookingApprovalWorkflow < BetterService::Workflows::Base
    step :fetch_booking,
         with: FetchBookingService,
         input: ->(ctx) { { booking_id: ctx.booking_id } }

    branch do
      # Auto-approve recent bookings (within 30 days)
      on ->(ctx) { ctx.fetch_booking.date <= 30.days.from_now.to_date } do
        step :auto_approve,
             with: AutoApproveBookingService,
             input: ->(ctx) { { booking: ctx.fetch_booking } }
      end

      # Manager approval for bookings within 90 days
      on ->(ctx) {
        ctx.fetch_booking.date > 30.days.from_now.to_date &&
        ctx.fetch_booking.date <= 90.days.from_now.to_date
      } do
        step :request_manager_approval,
             with: RequestManagerApprovalService,
             input: ->(ctx) { { booking: ctx.fetch_booking } }
      end

      # Executive approval for far-future bookings
      otherwise do
        step :request_executive_approval,
             with: RequestExecutiveApprovalService,
             input: ->(ctx) { { booking: ctx.fetch_booking } }
      end
    end

    step :send_notification,
         with: SendApprovalNotificationService
  end

  test "booking workflow - recent booking is auto-approved" do
    booking = Booking.create!(
      title: "Team Meeting",
      description: "Weekly team sync",
      date: 15.days.from_now.to_date,
      user: @user
    )

    workflow = BookingApprovalWorkflow.new(@user, params: { booking_id: booking.id })
    result = workflow.call

    assert result[:success]
    assert_equal [:fetch_booking, :auto_approve, :send_notification], result[:metadata][:steps_executed]
    assert_includes result[:metadata][:branches_taken], "branch_1:on_1"
    assert_equal "auto_approved", result[:context].auto_approve[:status]
  end

  test "booking workflow - medium-future booking requires manager approval" do
    booking = Booking.create!(
      title: "Conference Room",
      description: "Quarterly planning",
      date: 60.days.from_now.to_date,
      user: @user
    )

    workflow = BookingApprovalWorkflow.new(@user, params: { booking_id: booking.id })
    result = workflow.call

    assert result[:success]
    assert_equal [:fetch_booking, :request_manager_approval, :send_notification], result[:metadata][:steps_executed]
    assert_includes result[:metadata][:branches_taken], "branch_1:on_2"
    assert_equal "pending_manager", result[:context].request_manager_approval[:status]
  end

  test "booking workflow - far-future booking requires executive approval" do
    booking = Booking.create!(
      title: "Annual Conference",
      description: "Company-wide event",
      date: 120.days.from_now.to_date,
      user: @user
    )

    workflow = BookingApprovalWorkflow.new(@user, params: { booking_id: booking.id })
    result = workflow.call

    assert result[:success]
    assert_equal [:fetch_booking, :request_executive_approval, :send_notification], result[:metadata][:steps_executed]
    assert_includes result[:metadata][:branches_taken], "branch_1:otherwise"
    assert_equal "pending_executive", result[:context].request_executive_approval[:status]
  end

  # ============================================================================
  # Test Scenario 3: Transaction Rollback in Branches
  # ============================================================================

  class CreateProductService < BetterService::Services::Base
    schema do
      required(:name).filled(:string)
      required(:price).filled(:decimal)
    end

    process_with do |data|
      product = Product.create!(
        name: params[:name],
        price: params[:price],
        user: user
      )
      { resource: product }
    end
  end

  class FailingPublishService < BetterService::Services::Base
    schema do
      required(:product).filled
    end

    process_with do |data|
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

  test "branch failure triggers rollback of all database changes" do
    initial_count = Product.count

    error = assert_raises(BetterService::Errors::Workflowable::Runtime::WorkflowExecutionError) do
      workflow = ProductCreationWorkflow.new(
        @user,
        params: { product_name: "Test Product", product_price: 99.99, should_publish: true }
      )
      workflow.call
    end

    assert_match(/Publishing failed/, error.message)

    # Verify transaction was rolled back
    assert_equal initial_count, Product.count, "Product should not have been created due to rollback"
  end

  test "successful branch path commits all changes" do
    initial_count = Product.count

    workflow = ProductCreationWorkflow.new(
      @user,
      params: { product_name: "Draft Product", product_price: 49.99, should_publish: false }
    )
    result = workflow.call

    assert result[:success]
    assert_equal initial_count + 1, Product.count, "Product should have been created"
    assert Product.exists?(name: "Draft Product")
  end

  # ============================================================================
  # Test Scenario 4: Complex Multi-User Workflow with Branching
  # ============================================================================

  test "multi-user workflow with user-specific branches" do
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

    # Test as admin
    admin_result = workflow_class.new(admin_user, params: {}).call
    assert admin_result[:success]
    assert_equal [:validate, :admin_action], admin_result[:metadata][:steps_executed]
    assert admin_result[:context].admin_action[:admin_action]

    # Test as regular user
    user_result = workflow_class.new(regular_user, params: {}).call
    assert user_result[:success]
    assert_equal [:validate, :user_action], user_result[:metadata][:steps_executed]
    assert user_result[:context].user_action[:user_action]
  end

  # ============================================================================
  # Test Scenario 5: Branching with Database Queries
  # ============================================================================

  test "branch conditions can query database" do
    # Create products with different prices
    expensive = Product.create!(name: "Expensive", price: 500, user: @user)
    cheap = Product.create!(name: "Cheap", price: 10, user: @user)

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
          # Query database in condition
          Product.where("price > ?", 100).exists?(id: ctx.fetch_product.id)
        } do
          step :premium_handling, with: premium_service
        end

        otherwise do
          step :standard_handling, with: standard_service
        end
      end
    end

    # Test expensive product
    expensive_result = workflow_class.new(@user, params: { product_id: expensive.id }).call
    assert expensive_result[:success]
    assert_equal "premium", expensive_result[:context].premium_handling[:tier]

    # Test cheap product
    cheap_result = workflow_class.new(@user, params: { product_id: cheap.id }).call
    assert cheap_result[:success]
    assert_equal "standard", cheap_result[:context].standard_handling[:tier]
  end
end
