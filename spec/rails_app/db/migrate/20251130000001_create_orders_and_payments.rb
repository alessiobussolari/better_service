# frozen_string_literal: true

class CreateOrdersAndPayments < ActiveRecord::Migration[7.1]
  def change
    # Add admin and seller flags to users
    add_column :users, :admin, :boolean, default: false, null: false
    add_column :users, :seller, :boolean, default: false, null: false

    # Add stock column to products for inventory management
    add_column :products, :stock, :integer, default: 100, null: false

    # Orders table
    create_table :orders do |t|
      t.references :user, null: false, foreign_key: true
      t.decimal :total, precision: 10, scale: 2, null: false
      t.integer :status, default: 0, null: false
      t.integer :payment_method, default: 0, null: false

      t.timestamps
    end

    # Order items table
    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.integer :quantity, null: false
      t.decimal :unit_price, precision: 10, scale: 2, null: false

      t.timestamps
    end

    # Payments table
    create_table :payments do |t|
      t.references :order, null: false, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.integer :status, default: 0, null: false
      t.integer :provider, default: 0, null: false
      t.string :transaction_id
      t.string :refund_id
      t.datetime :completed_at
      t.datetime :refunded_at
      t.text :metadata

      t.timestamps
    end

    # Indexes
    add_index :orders, :status
    add_index :orders, :payment_method
    add_index :payments, :status
    add_index :payments, :transaction_id, unique: true
  end
end
