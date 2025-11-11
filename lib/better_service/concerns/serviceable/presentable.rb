# frozen_string_literal: true

module BetterService
  module Concerns
    module Serviceable
    module Presentable
      extend ActiveSupport::Concern

      included do
        class_attribute :_presenter_class, default: nil
        class_attribute :_presenter_options, default: -> { {} }
      end

      class_methods do
        def presenter(klass)
          self._presenter_class = klass
        end

        def presenter_options(&block)
          self._presenter_options = block
        end
      end

      private

      # Override transform phase
      def transform(data)
        # If custom transform_with block defined, use it
        if self.class._transform_block
          instance_exec(data, &self.class._transform_block)
        # If presenter configured, apply it
        elsif self.class._presenter_class
          apply_presenter(data)
        # Otherwise return data unchanged
        else
          data
        end
      end

      def apply_presenter(data)
        options = instance_exec(&self.class._presenter_options)

        if data.key?(:items)
          rest = data.dup
          rest.delete(:items)
          { items: present_collection(data[:items], options), **rest }
        elsif data.key?(:resource)
          rest = data.dup
          rest.delete(:resource)
          { resource: present_resource(data[:resource], options), **rest }
        else
          data
        end
      end

      def present_collection(items, options)
        items.map { |item| self.class._presenter_class.new(item, **options) }
      end

      def present_resource(resource, options)
        self.class._presenter_class.new(resource, **options)
      end
    end
    end
  end
end
