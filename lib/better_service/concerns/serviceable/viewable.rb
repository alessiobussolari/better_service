# frozen_string_literal: true

module BetterService
  module Concerns
    module Serviceable
    module Viewable
      extend ActiveSupport::Concern

      included do
        class_attribute :_viewer_enabled, default: false
        class_attribute :_viewer_block, default: nil
      end

      class_methods do
        def viewer(enabled = true, &block)
          self._viewer_enabled = enabled
          self._viewer_block = block if block_given?
        end
      end

      private

      def viewer_enabled?
        self.class._viewer_enabled && self.class._viewer_block.present?
      end

      def execute_viewer(processed, transformed, result)
        instance_exec(processed, transformed, result, &self.class._viewer_block)
      end
    end
    end
  end
end
