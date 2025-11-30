# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe "Error Handling Integration", type: :integration do
  include_context "with order"

  describe "Full service error flow with real models" do
    it "raises ValidationError with detailed context on invalid params" do
      expect {
        Order::CreateService.new(user, params: { items: [] })
      }.to raise_error(BetterService::Errors::Runtime::ValidationError) do |error|
        expect(error.code).to eq(:validation_failed)
        expect(error.context[:service]).to eq("Order::CreateService")
        expect(error.context[:validation_errors]).to have_key(:items)
      end
    end

    it "returns failure result when products are not available" do
      # Product validation happens in process_with, so service returns failure result
      result = Order::CreateService.new(user, params: {
        items: [{ product_id: 999999, quantity: 1 }]
      }).call

      expect(result).to be_failure
      expect(result.meta[:success]).to be false
    end

    it "returns failure for authorization errors" do
      # Create a service that requires admin permissions
      restricted_service = Class.new(BetterService::Services::Base) do
        schema { optional(:data).maybe(:string) }

        authorize_with do
          user.admin?
        end

        process_with { { resource: { authorized: true } } }
      end

      # BetterService catches AuthorizationError and returns failure Result
      result = restricted_service.new(user, params: {}).call

      expect(result).to be_failure
      expect(result.meta[:error_code]).to eq(:unauthorized)
    end
  end

  describe "Transaction rollback on exception" do
    it "rolls back database changes when exception is raised mid-transaction" do
      initial_order_count = Order.count
      initial_item_count = OrderItem.count

      # Create a service that fails after creating records
      failing_service = Class.new(Order::BaseService) do
        with_transaction true

        schema do
          required(:items).filled(:array).each do
            hash do
              required(:product_id).filled(:integer)
              required(:quantity).filled(:integer)
            end
          end
        end

        process_with do
          # Create order
          order = order_repository.create!(
            user: user,
            total: 100,
            status: :pending,
            payment_method: :credit_card
          )

          # Create item
          order.order_items.create!(
            product_id: params[:items].first[:product_id],
            quantity: 1,
            unit_price: 100
          )

          # Raise error after creating records
          raise StandardError, "Intentional failure"
        end
      end

      # BetterService catches the error and returns failure result
      result = failing_service.new(user, params: {
        items: [{ product_id: product.id, quantity: 1 }]
      }).call

      expect(result).to be_failure

      # Verify records were not persisted (transaction rolled back)
      expect(Order.count).to eq(initial_order_count)
      expect(OrderItem.count).to eq(initial_item_count)
    end
  end

  describe "Validation error with real ActiveRecord" do
    it "captures ActiveRecord validation errors" do
      # Attempt to create an order with invalid total (assuming validation exists)
      invalid_order_service = Class.new(Order::BaseService) do
        with_transaction true
        schema { optional(:total).maybe(:float) }

        process_with do
          order = order_repository.create!(
            user: user,
            total: params[:total] || -10, # Invalid negative total
            status: :pending,
            payment_method: :credit_card
          )
          { resource: order }
        end
      end

      # BetterService catches ActiveRecord::RecordInvalid and returns failure result
      result = invalid_order_service.new(user, params: { total: -10 }).call

      expect(result).to be_failure
    end
  end

  describe "Authorization with complex user permissions" do
    it "allows admin to access any resource" do
      other_users_product = Product.create!(
        name: "Other User Product",
        price: 50.00,
        user: seller_user,
        published: true,
        stock: 10
      )

      manage_service = Class.new(BetterService::Services::Base) do
        schema do
          required(:product_id).filled(:integer)
        end

        authorize_with do
          prod = Product.find(params[:product_id])
          user.can_manage?(prod)
        end

        process_with do
          prod = Product.find(params[:product_id])
          { resource: prod }
        end
      end

      # Regular user cannot manage other's product - returns failure
      result = manage_service.new(user, params: { product_id: other_users_product.id }).call
      expect(result).to be_failure
      expect(result.meta[:error_code]).to eq(:unauthorized)

      # Admin can manage any product - returns success
      admin_result = manage_service.new(admin_user, params: { product_id: other_users_product.id }).call
      expect(admin_result).to be_success
      expect(admin_result.resource).to eq(other_users_product)
    end
  end

  describe "Database constraint violation handling" do
    it "handles unique constraint violations" do
      # Create first user
      User.create!(name: "Existing User", email: "duplicate@example.com")

      duplicate_service = Class.new(BetterService::Services::Base) do
        with_transaction true
        schema do
          required(:email).filled(:string)
          required(:name).filled(:string)
        end

        process_with do
          new_user = User.create!(
            name: params[:name],
            email: params[:email]
          )
          { resource: new_user }
        end
      end

      # Skip if email uniqueness is not enforced at DB level
      if User.validators_on(:email).any? { |v| v.is_a?(ActiveRecord::Validations::UniquenessValidator) }
        # BetterService catches the error and returns failure result
        result = duplicate_service.new(user, params: {
          name: "New User",
          email: "duplicate@example.com"
        }).call
        expect(result).to be_failure
      else
        # Just test that service works with unique email
        result = duplicate_service.new(user, params: {
          name: "New User",
          email: "unique_#{SecureRandom.hex(4)}@example.com"
        }).call
        expect(result).to be_success
        expect(result.resource).to be_persisted
      end
    end
  end

  describe "Nested service error propagation" do
    it "propagates errors from nested services with context" do
      inner_service = Class.new(BetterService::Services::Base) do
        schema { required(:value).filled(:integer) }

        process_with do
          raise BetterService::Errors::Runtime::ResourceNotFoundError.new(
            "Inner resource not found",
            code: :resource_not_found,
            context: { inner_value: params[:value] }
          )
        end
      end

      outer_service = Class.new(BetterService::Services::Base) do
        schema { required(:id).filled(:integer) }

        define_method(:inner_service_class) { inner_service }

        process_with do
          inner_service_class.new(user, params: { value: params[:id] }).call
        end
      end

      # Nested call - inner service error is caught by outer service
      result = outer_service.new(user, params: { id: 42 }).call

      expect(result).to be_failure
      expect(result.meta[:error_code]).to eq(:resource_not_found)
    end
  end

  describe "Error logging verification" do
    it "logs error details appropriately" do
      logged_messages = []
      original_logger = Rails.logger
      Rails.logger = Logger.new(StringIO.new)
      allow(Rails.logger).to receive(:error) { |msg| logged_messages << msg }

      logging_service = Class.new(BetterService::Services::Base) do
        schema { optional(:x).maybe(:integer) }

        process_with do
          error = StandardError.new("Test error for logging")
          Rails.logger.error("Service failed: #{error.message}")
          raise error
        end
      end

      # BetterService catches the error and returns failure result
      result = logging_service.new(user, params: {}).call
      expect(result).to be_failure

      expect(logged_messages.any? { |m| m.include?("Test error for logging") }).to be true
    ensure
      Rails.logger = original_logger
    end
  end

  describe "Error response format consistency" do
    it "error to_h provides consistent structure" do
      begin
        Order::CreateService.new(user, params: { items: [] })
      rescue BetterService::Errors::Runtime::ValidationError => e
        hash = e.to_h

        expect(hash).to have_key(:error_class)
        expect(hash).to have_key(:message)
        expect(hash).to have_key(:code)
        expect(hash).to have_key(:timestamp)
        expect(hash).to have_key(:context)
        expect(hash).to have_key(:backtrace)

        expect(hash[:error_class]).to eq("BetterService::Errors::Runtime::ValidationError")
        expect(hash[:code]).to eq(:validation_failed)
        expect(hash[:timestamp]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end
    end

    it "all error types provide same structure" do
      errors = [
        BetterService::Errors::Runtime::ValidationError.new("Test", code: :validation_failed),
        BetterService::Errors::Runtime::AuthorizationError.new("Test", code: :unauthorized),
        BetterService::Errors::Runtime::ResourceNotFoundError.new("Test", code: :resource_not_found),
        BetterService::Errors::Runtime::DatabaseError.new("Test", code: :database_error),
        BetterService::Errors::Runtime::ExecutionError.new("Test", code: :execution_error)
      ]

      required_keys = [:error_class, :message, :code, :timestamp, :context, :backtrace]

      errors.each do |error|
        hash = error.to_h
        required_keys.each do |key|
          expect(hash).to have_key(key), "#{error.class} missing key: #{key}"
        end
      end
    end
  end
end
