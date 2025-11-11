# frozen_string_literal: true

module BetterService
  module Concerns
    module Serviceable
    module Messageable
      extend ActiveSupport::Concern

      included do
        class_attribute :_messages_namespace, default: nil
      end

      class_methods do
        def messages_namespace(namespace)
          self._messages_namespace = namespace
        end
      end

      private

      def message(key_path, interpolations = {})
        return key_path if self.class._messages_namespace.nil?

        full_key = "#{self.class._messages_namespace}.services.#{key_path}"
        I18n.t(full_key, **interpolations)
      end
    end
    end
  end
end
