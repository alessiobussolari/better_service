if defined?(Rails)
  module BetterService
    class Railtie < ::Rails::Railtie
      # Initialize subscribers after Rails boots
      #
      # This hook runs after all initializers have been executed,
      # ensuring BetterService.configuration is fully loaded.
      config.after_initialize do
        # Attach LogSubscriber if enabled in configuration
        if BetterService.configuration.log_subscriber_enabled
          BetterService::Subscribers::LogSubscriber.attach
          Rails.logger.info "[BetterService] LogSubscriber attached" if Rails.logger
        end

        # Attach StatsSubscriber if enabled in configuration
        if BetterService.configuration.stats_subscriber_enabled
          BetterService::Subscribers::StatsSubscriber.attach
          Rails.logger.info "[BetterService] StatsSubscriber attached" if Rails.logger
        end
      end
    end
  end
end
