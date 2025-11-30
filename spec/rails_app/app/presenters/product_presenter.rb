# frozen_string_literal: true

class ProductPresenter < BetterService::Presenter
  def as_json(opts = {})
    {
      id: object.id,
      name: object.name,
      price: object.price,
      formatted_price: formatted_price,
      published: object.published?,
      in_stock: object.in_stock?,
      created_at: object.created_at&.iso8601
    }.tap do |json|
      json[:owner] = owner_info if include_field?(:owner)
      json[:stock] = object.stock if current_user&.admin?
      json[:can_edit] = user_can?(:edit) if current_user
      json[:can_delete] = user_can?(:delete) if current_user
    end
  end

  private

  def formatted_price
    "$#{object.price}" if object.price
  end

  def owner_info
    return nil unless object.user

    {
      id: object.user_id,
      name: object.user.name
    }
  end

  def user_can?(action)
    return false unless current_user

    case action
    when :edit
      current_user.admin? || current_user.id == object.user_id
    when :delete
      current_user.admin?
    else
      false
    end
  end
end
