# frozen_string_literal: true

require "spec_helper"

RSpec.describe OrderRepository do
  include_context "with order"

  let(:repository) { described_class.new }

  describe "#find" do
    it "finds order by id" do
      found = repository.find(order.id)
      expect(found).to eq(order)
    end

    it "raises error for non-existent id" do
      expect {
        repository.find(999999)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#by_user" do
    it "returns orders for specified user" do
      orders = repository.by_user(user)
      expect(orders).to include(order)
    end

    it "excludes other users orders" do
      other_user = User.create!(name: "Other", email: "other@example.com")
      other_order = Order.create!(
        user: other_user,
        total: 50.00,
        status: :pending,
        payment_method: :credit_card
      )

      orders = repository.by_user(user)
      expect(orders).not_to include(other_order)
    end
  end

  describe "#by_status" do
    it "returns orders with specified status" do
      orders = repository.by_status(:pending)
      expect(orders).to include(order)
    end

    it "excludes orders with different status" do
      orders = repository.by_status(:paid)
      expect(orders).not_to include(order)
    end
  end

  describe "#with_items" do
    it "eager loads order items" do
      result = repository.with_items.find(order.id)
      expect(result.association(:order_items)).to be_loaded
    end
  end

  describe "#full_details" do
    it "eager loads all associations" do
      result = repository.full_details.find(order.id)
      expect(result.association(:order_items)).to be_loaded
    end
  end

  describe "#recent" do
    it "orders by created_at descending" do
      older_order = Order.create!(
        user: user,
        total: 25.00,
        status: :pending,
        payment_method: :credit_card,
        created_at: 1.day.ago
      )
      newer_order = Order.create!(
        user: user,
        total: 50.00,
        status: :pending,
        payment_method: :credit_card,
        created_at: Time.current
      )

      orders = repository.recent.to_a
      expect(orders.size).to be >= 2
      expect(orders.first).to eq(newer_order)
      expect(orders.last).to eq(older_order)
    end
  end

  describe "#create!" do
    it "creates a new order" do
      new_order = repository.create!(
        user: user,
        total: 150.00,
        status: :pending,
        payment_method: :paypal
      )

      expect(new_order).to be_persisted
      expect(new_order.total).to eq(150.00)
    end
  end

  describe "#update!" do
    it "updates order attributes" do
      repository.update!(order, status: :confirmed)
      order.reload
      expect(order.status).to eq("confirmed")
    end
  end

  describe "#destroy!" do
    it "destroys the order" do
      order_id = order.id
      repository.destroy!(order)
      expect(Order.find_by(id: order_id)).to be_nil
    end
  end
end
