# frozen_string_literal: true

module BetterService
  # Result wrapper per le risposte dei service
  #
  # Fornisce un modo standardizzato per restituire sia la risorsa che i metadata.
  # BetterController può automaticamente unwrappare gli oggetti Result.
  #
  # @example Caso di successo
  #   BetterService::Result.new(user, meta: { message: "Created" })
  #
  # @example Caso di fallimento
  #   BetterService::Result.new(user, meta: { success: false, message: "Validation failed" })
  #
  class Result
    attr_reader :resource, :meta

    # @param resource [Object] L'oggetto risorsa (model, collection, etc.)
    # @param meta [Hash] Hash di metadata, deve contenere :success key (default: true)
    def initialize(resource, meta: {})
      @resource = resource
      @meta     = meta.is_a?(Hash) ? meta.reverse_merge(success: true) : { success: true }
    end

    # @return [Boolean] true se l'operazione è riuscita
    def success?
      meta[:success] == true
    end

    # @return [Boolean] true se l'operazione è fallita
    def failure?
      !success?
    end

    # @return [String, nil] Il messaggio dal meta
    def message
      meta[:message]
    end

    # @return [Symbol, nil] L'azione eseguita
    def action
      meta[:action]
    end

    # @return [Hash, nil] Gli errori di validazione
    def validation_errors
      meta[:validation_errors]
    end

    # @return [Array<String>, nil] I messaggi di errore completi
    def full_messages
      meta[:full_messages]
    end

    # @return [ActiveModel::Errors, nil] Errori dalla risorsa se disponibili
    def errors
      resource.respond_to?(:errors) ? resource.errors : nil
    end

    # Supporta destructuring: resource, meta = result
    # @return [Array] [resource, meta]
    def to_ary
      [resource, meta]
    end

    # Alias per compatibilità con destructuring
    alias_method :deconstruct, :to_ary

    # @return [Hash] Rappresentazione completa
    def to_h
      { resource: resource, meta: meta }
    end
  end
end
